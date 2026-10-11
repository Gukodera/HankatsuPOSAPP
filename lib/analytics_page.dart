import 'dart:async';
import 'package:flutter/material.dart';
import 'pos_api.dart';
import 'pos_header.dart';
import 'filter_chip.dart';
import 'list_controls.dart';
import 'receipt.dart';
import 'export_file.dart';
import 'pdf_export.dart';
import 'export_notice.dart';

DateTime periodStart(DateTime date, String period) => period == 'monthly'
    ? DateTime(date.year, date.month)
    : period == 'weekly'
    ? DateTime(date.year, date.month, date.day - date.weekday + 1)
    : DateTime(date.year, date.month, date.day);
DateTime shiftPeriod(DateTime date, String period, int delta) {
  final start = periodStart(date, period);
  return period == 'monthly'
      ? DateTime(start.year, start.month + delta)
      : DateTime(
          start.year,
          start.month,
          start.day + (period == 'weekly' ? 7 : 1) * delta,
        );
}

String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class AnalyticsPage extends StatefulWidget {
  final PosApi api;
  final Json staff;
  final bool invoicesOnly;
  final String initialPeriod;
  final DateTime? initialDate;
  const AnalyticsPage({
    super.key,
    required this.api,
    required this.staff,
    this.invoicesOnly = false,
    this.initialPeriod = 'daily',
    this.initialDate,
  });
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late String period;
  late DateTime date;
  String payment = 'all', query = '';
  String? error;
  Json? report;
  List<Json> invoices = [];
  final cursors = <Json>[{}];
  int count = 0, generation = 0;
  bool loading = true, exporting = false;
  Timer? debounce;
  final search = TextEditingController();
  bool get admin => widget.staff['role'] == 'admin';
  Json get args => {
    'period': period,
    'date': dateKey(date),
    'query': query,
    'payment': payment,
    if (report != null) 'as_of': report!['as_of'],
  };
  @override
  void initState() {
    super.initState();
    period = widget.initialPeriod;
    date = widget.initialDate ?? DateTime.parse(widget.staff['business_date']);
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool refresh = true}) async {
    final token = ++generation;
    setState(() => loading = true);
    try {
      Json? summary = report;
      if (refresh || summary == null) {
        summary = Json.from(
          await widget.api.call('report', {
            'period': period,
            'date': dateKey(date),
          }),
        );
        cursors
          ..clear()
          ..add({});
      }
      final data = widget.invoicesOnly
          ? Json.from(
              await widget.api.call('invoices', {
                'period': period,
                'date': dateKey(date),
                'as_of': summary['as_of'],
                'query': query,
                'payment': payment,
                ...cursors.last,
              }),
            )
          : null;
      if (mounted && token == generation) {
        setState(() {
          report = summary;
          invoices = data == null ? [] : List<Json>.from(data['rows']);
          count = data?['count'] ?? 0;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && token == generation) {
        setState(() {
          error = errorMessage(e);
          loading = false;
        });
      }
    }
  }

  void changePeriod(String value) {
    setState(() => period = value);
    load();
  }

  Future<void> details(Json row) async {
    try {
      final receipt = Json.from(
        await widget.api.call('invoice', {'id': row['id']}),
      );
      if (!mounted) return;
      if (admin && !receipt['legacy'] && receipt['payment_status'] == 'paid') {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(receipt['receipt']),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'view'),
                child: const Text('View / print receipt'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'reverse'),
                child: const Text('Refund / void with reason'),
              ),
            ],
          ),
        );
        if (choice == 'reverse' && mounted) {
          await reverse(receipt);
          return;
        }
        if (choice != 'view') return;
      }
      if (mounted) await showReceipt(context, receipt);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  Future<void> reverse(Json receipt) async {
    final reason = TextEditingController();
    String type = 'refunded';
    bool restock = false, busy = false;
    String? failure;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('Correct ${receipt['receipt']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Returns ${moneyMinor(receipt['total_minor'])} from your open cash shift. The original receipt stays in history.',
                ),
                DropdownButton<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'refunded', child: Text('Refund')),
                    DropdownMenuItem(value: 'voided', child: Text('Void')),
                  ],
                  onChanged: busy ? null : (v) => update(() => type = v!),
                ),
                TextField(
                  controller: reason,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
                CheckboxListTile(
                  value: restock,
                  onChanged: busy ? null : (v) => update(() => restock = v!),
                  title: const Text('Return items to sellable stock'),
                  subtitle: const Text(
                    'Leave off for prepared or wasted food.',
                  ),
                ),
                if (failure != null) Text(failure!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (reason.text.trim().length < 3) {
                        update(() => failure = 'Enter a reason');
                        return;
                      }
                      if (!await confirmAction(
                        ctx,
                        title: 'Confirm reversal?',
                        message:
                            '${receipt['receipt']}\n${moneyMinor(receipt['total_minor'])} returned\nRestock: ${restock ? 'Yes' : 'No'}\n${reason.text.trim()}',
                        confirmLabel: 'Confirm reversal',
                      )) {
                        return;
                      }
                      update(() => busy = true);
                      try {
                        await widget.api.call('reverse', {
                          'id': receipt['id'],
                          'target': type,
                          'reason': reason.text.trim(),
                          'restock': restock,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          update(() => failure = errorMessage(e));
                        }
                      } finally {
                        if (ctx.mounted) update(() => busy = false);
                      }
                    },
              child: const Text('Review reversal'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    reason.dispose();
    await load();
  }

  Future<void> export() async {
    if (report == null || exporting) return;
    setState(() => exporting = true);
    try {
      final summary =
          'HANKATSU ${period.toUpperCase()} SUMMARY\n${report!['scope']} • Asia/Manila\n${report!['start']} to ${report!['end']}\nSnapshot: ${report!['as_of']}\nTransactions: ${report!['count']}\nGross: ${moneyMinor(report!['gross_minor'])}\nReversals recorded this period: ${moneyMinor(report!['reversal_minor'])}\nNet: ${moneyMinor(report!['net_minor'])}';
      if (!widget.invoicesOnly) {
        final message = await exportBytes(
          'hankatsu-$period-${dateKey(date)}.pdf',
          () => periodSummaryPdf(summary),
          'application/pdf',
        );
        if (mounted) {
          showExportNotice(context, message);
        }
      } else {
        Future<String> buildCsv() async {
          final data = <Json>[];
          Json cursor = {};
          while (true) {
            final page = Json.from(
              await widget.api.call('export', {...args, ...cursor}),
            );
            final rows = List<Json>.from(page['rows']);
            if (rows.isEmpty) break;
            data.addAll(rows);
            cursor = {
              'cursor_time': rows.last['created_at'],
              'cursor_id': rows.last['id'],
            };
          }
          String cell(dynamic value) {
            var s = value.toString();
            if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
            return '"${s.replaceAll('"', '""')}"';
          }

          final csv = [
            'Receipt,Customer,Created UTC,Total PHP,Payment status',
            for (final row in data)
              [
                row['receipt'],
                row['customer_name'],
                row['created_at'],
                (row['total_minor'] / 100).toStringAsFixed(2),
                row['payment_status'],
              ].map(cell).join(','),
          ].join('\r\n');
          return csv;
        }

        final message = await exportFile(
          'invoices-$period-${dateKey(date)}.csv',
          buildCsv,
          'text/csv',
        );
        if (mounted) {
          showExportNotice(context, message);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PosHeader(
            title: widget.invoicesOnly ? 'Invoice archive' : 'Sales overview',
            subtitle:
                '${admin ? 'Store' : 'My sales'} • Asia/Manila • midnight cutoff',
            icon: widget.invoicesOnly ? Icons.receipt_long : Icons.insights,
            actions: IconButton(
              tooltip: 'Refresh reports',
              onPressed: load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final p in ['daily', 'weekly', 'monthly'])
                PosFilterChip(
                  label: p[0].toUpperCase() + p.substring(1),
                  selected: period == p,
                  onSelected: (_) => changePeriod(p),
                ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous period',
                onPressed: () {
                  setState(() => date = shiftPeriod(date, period, -1));
                  load();
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().toUtc().add(
                        const Duration(hours: 8, days: 1),
                      ),
                    );
                    if (selected != null) {
                      setState(() => date = selected);
                      load();
                    }
                  },
                  child: Text(dateKey(periodStart(date, period))),
                ),
              ),
              IconButton(
                tooltip: 'Next period',
                onPressed:
                    periodStart(shiftPeriod(date, period, 1), period).isAfter(
                      DateTime.now().toUtc().add(const Duration(hours: 8)),
                    )
                    ? null
                    : () {
                        setState(() => date = shiftPeriod(date, period, 1));
                        load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          if (report != null && !loading && error == null) ...[
            Text(
              'Snapshot ${report!['as_of']}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (!widget.invoicesOnly) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF191519),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NET SALES',
                      style: TextStyle(
                        color: Color(0xFFFCE2E8),
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      moneyMinor(report!['net_minor']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${report!['count']} transactions',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Gross sales'),
                trailing: Text(moneyMinor(report!['gross_minor'])),
              ),
              ListTile(
                title: const Text('Reversals recorded this period'),
                trailing: Text(moneyMinor(report!['reversal_minor'])),
              ),
              const Text(
                'A reversal is counted on its correction date, even when the original sale belongs to an earlier period.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sales activity',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              for (final bucket in List<Json>.from(report!['buckets']))
                ListTile(
                  title: Text(bucket['bucket']),
                  trailing: Text(moneyMinor(bucket['total_minor'])),
                ),
              const Text(
                'Best sellers · gross units',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              for (final b in List<Json>.from(report!['best']))
                ListTile(
                  title: Text(b['product_name']),
                  trailing: Text('${b['qty']} sold'),
                ),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AnalyticsPage(
                      api: widget.api,
                      staff: widget.staff,
                      invoicesOnly: true,
                      initialPeriod: period,
                      initialDate: date,
                    ),
                  ),
                ),
                icon: const Icon(Icons.receipt_long),
                label: Text('Browse $period invoices'),
              ),
            ] else ...[
              TextField(
                controller: search,
                onChanged: (v) {
                  query = v;
                  cursors
                    ..clear()
                    ..add({});
                  debounce?.cancel();
                  debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => load(refresh: false),
                  );
                },
                decoration: const InputDecoration(
                  labelText: 'Customer or receipt number',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in [
                    'all',
                    'paid',
                    'refunded',
                    'voided',
                    'legacy',
                  ])
                    PosFilterChip(
                      label: s,
                      selected: payment == s,
                      onSelected: (_) {
                        setState(() => payment = s);
                        cursors
                          ..clear()
                          ..add({});
                        load(refresh: false);
                      },
                    ),
                ],
              ),
              Text('$count matching invoices • 10 per page'),
              if (invoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No matching invoices.'),
                ),
              for (final invoice in invoices)
                Card(
                  child: ListTile(
                    title: Text(invoice['customer_name']),
                    subtitle: Text(
                      '${invoice['receipt']}\n${invoice['payment_status']}',
                    ),
                    trailing: Text(moneyMinor(invoice['total_minor'])),
                    onTap: () => details(invoice),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: cursors.length == 1
                        ? null
                        : () {
                            cursors.removeLast();
                            load(refresh: false);
                          },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Page ${cursors.length}'),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: invoices.length < 10
                        ? null
                        : () {
                            cursors.add({
                              'cursor_time': invoices.last['created_at'],
                              'cursor_id': invoices.last['id'],
                            });
                            load(refresh: false);
                          },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: exporting ? null : export,
              icon: const Icon(Icons.download),
              label: Text(
                exporting
                    ? 'Exporting…'
                    : widget.invoicesOnly
                    ? 'Export matching invoices (CSV)'
                    : 'Export period summary (PDF)',
              ),
            ),
          ],
        ],
      ),
    );
    return widget.invoicesOnly
        ? Scaffold(
            appBar: AppBar(title: const Text('Invoices')),
            body: SafeArea(child: body),
          )
        : body;
  }
}

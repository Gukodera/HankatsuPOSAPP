import 'package:flutter/material.dart';
import 'pos_api.dart';
import 'pos_header.dart';
import 'list_controls.dart';

class ShiftPage extends StatefulWidget {
  final PosApi api;
  final bool admin;
  const ShiftPage({super.key, required this.api, required this.admin});
  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> {
  Json? shift;
  String? error;
  bool busy = false;
  List<Json> history = [];
  int page = 0;
  bool visible = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextVisible = TickerMode.valuesOf(context).enabled;
    if (nextVisible && !visible) load();
    visible = nextVisible;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.api.call('shift');
      final past = widget.admin
          ? await widget.api.call('shift_history', {'offset': page * 10})
          : [];
      if (mounted) {
        setState(() {
          shift = data == null ? null : Json.from(data);
          history = List<Json>.from(past);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
  }

  Future<void> edit(String action) async {
    final amount = TextEditingController(), note = TextEditingController();
    bool submitting = false;
    String? formError;
    final request = requestId();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            action == 'open_shift'
                ? 'Open cash shift'
                : action == 'close_shift'
                ? 'Close and reconcile'
                : 'Cash in / out',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (action == 'close_shift')
                  Text('Expected ${moneyMinor(shift?['expected_minor'] ?? 0)}'),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: action == 'open_shift'
                        ? 'Opening cash'
                        : action == 'close_shift'
                        ? 'Counted cash'
                        : 'Amount (negative for cash out)',
                  ),
                ),
                if (action != 'open_shift')
                  TextField(
                    controller: note,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Reason / closing note',
                    ),
                  ),
                if (formError != null)
                  Text(formError!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final raw = amount.text.trim();
                      final minor = parseMinor(
                        raw.startsWith('-') ? raw.substring(1) : raw,
                      );
                      if (minor == null) {
                        update(() => formError = 'Enter a valid amount');
                        return;
                      }
                      if (!await confirmAction(
                        ctx,
                        title: 'Confirm cash record',
                        message: '${amount.text}\n${note.text}',
                        confirmLabel: 'Confirm',
                      )) {
                        return;
                      }
                      update(() => submitting = true);
                      try {
                        await widget.api.call(action, {
                          'request_id': request,
                          'opening_minor': minor,
                          'counted_minor': minor,
                          'amount_minor': raw.startsWith('-') ? -minor : minor,
                          'reason': note.text.trim(),
                          'note': note.text.trim(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          update(() => formError = errorMessage(e));
                        }
                      } finally {
                        if (ctx.mounted) update(() => submitting = false);
                      }
                    },
              child: Text(submitting ? 'Saving…' : 'Continue'),
            ),
          ],
        ),
      ),
    );
    // Controllers are retained until the route finishes its exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    amount.dispose();
    note.dispose();
    await load();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PosHeader(
          title: 'Cash shift',
          subtitle:
              'Manage opening cash, cash movements and the closing count.',
          icon: Icons.point_of_sale,
          actions: IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Open a shift with the cash already in your drawer. Sales and refunds update expected cash. Record other cash added or removed, then count the drawer when closing.',
          ),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        const SizedBox(height: 16),
        if (shift == null)
          FilledButton(
            onPressed: () => edit('open_shift'),
            child: const Text('Open shift before selling'),
          )
        else ...[
          Text(
            'Expected cash ${moneyMinor(shift!['expected_minor'])}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          Text('Opening ${moneyMinor(shift!['opening_minor'])}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: () => edit('cash_movement'),
                child: const Text('Cash in / out'),
              ),
              FilledButton(
                onPressed: () => edit('close_shift'),
                child: const Text('Close shift'),
              ),
            ],
          ),
          for (final event in List<Json>.from(shift!['events'] ?? []))
            ListTile(
              title: Text(event['reason']),
              subtitle: Text(event['created_at']),
              trailing: Text(moneyMinor(event['amount_minor'])),
            ),
        ],
        if (widget.admin) ...[
          const Divider(),
          const Text(
            'Shift history',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          for (final s in history)
            Card(
              child: ListTile(
                title: Text(s['actor_name'] ?? s['actor_id']),
                subtitle: Text(
                  '${s['opened_at']}\n${s['closed_at'] == null ? 'Open' : 'Expected ${moneyMinor(s['expected_minor'])} / counted ${moneyMinor(s['counted_minor'])}'}\n${s['close_note'] ?? ''}',
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: page == 0
                    ? null
                    : () {
                        setState(() => page--);
                        load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${page + 1}'),
              IconButton(
                onPressed: history.length < 10
                    ? null
                    : () {
                        setState(() => page++);
                        load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

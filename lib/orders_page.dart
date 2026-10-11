import 'dart:async';
import 'package:flutter/material.dart';
import 'pos_api.dart';
import 'pos_header.dart';
import 'filter_chip.dart';
import 'list_controls.dart';

class OrdersPage extends StatefulWidget {
  final PosApi api;
  final String role;
  const OrdersPage({super.key, required this.api, this.role = 'admin'});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with WidgetsBindingObserver {
  List<Json> rows = [];
  final cursors = <Json>[{}];
  String status = 'queued', query = '';
  String? error, updated;
  int count = 0, generation = 0;
  bool loading = true, mutating = false, foreground = true, visible = true;
  Timer? timer, debounce;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextVisible = TickerMode.valuesOf(context).enabled;
    if (nextVisible && !visible) load();
    visible = nextVisible;
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (visible && foreground) {
      timer = Timer.periodic(const Duration(seconds: 15), (_) => load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
    if (foreground && visible) load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final token = ++generation;
    try {
      final data = Json.from(
        await widget.api.call('orders', {
          'status': status,
          'query': query,
          ...cursors.last,
        }),
      );
      if (!mounted || token != generation) return;
      setState(() {
        rows = List<Json>.from(data['rows']);
        count = data['count'];
        updated = data['refreshed_at'];
        error = null;
        loading = false;
      });
    } catch (e) {
      if (mounted && token == generation) {
        setState(() {
          error = errorMessage(e);
          loading = false;
        });
      }
    }
  }

  Future<void> advance(Json order, {bool reopen = false}) async {
    if (mutating) return;
    String? reason;
    final next = {
      'queued': 'preparing',
      'preparing': 'ready',
      'ready': 'served',
    }[order['service_status']];
    if (reopen) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reopen order'),
          content: TextField(
            controller: controller,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Correction reason'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      controller.dispose();
      if (reason == null || reason.length < 3 || !mounted) return;
    }
    if (!mounted) return;
    setState(() => mutating = true);
    try {
      if (!await confirmAction(
        context,
        title: reopen ? 'Return to queue?' : 'Mark as $next?',
        message:
            '${order['receipt']} • ${order['customer_name']}\n${order['order_type']} ${order['table_reference'] ?? ''}\n${reopen ? reason : 'Confirm after completing this step.'}',
        confirmLabel: reopen ? 'Reopen' : 'Confirm',
      )) {
        return;
      }
      await widget.api.call(reopen ? 'reopen' : 'transition', {
        'id': order['id'],
        'expected_status': order['service_status'],
        'target': next,
        'reason': reason,
      });
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PosHeader(
          title: 'Service desk',
          subtitle:
              '$count ${status == 'queued' ? 'waiting' : status} • 10 tickets per page',
          icon: Icons.room_service_outlined,
          actions: IconButton(
            tooltip: 'Refresh orders',
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) {
            query = value;
            cursors
              ..clear()
              ..add({});
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 300), load);
          },
          decoration: const InputDecoration(
            labelText: 'Customer, table or receipt',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in [
              'queued',
              'preparing',
              'ready',
              'served',
              'cancelled',
            ])
              PosFilterChip(
                label: s[0].toUpperCase() + s.substring(1),
                selected: status == s,
                onSelected: (_) {
                  setState(() {
                    status = s;
                    cursors
                      ..clear()
                      ..add({});
                    loading = true;
                  });
                  load();
                },
              ),
          ],
        ),
        if (updated != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Last refreshed ${DateTime.parse(updated!).toUtc().add(const Duration(hours: 8)).toString().substring(11, 19)} Manila • 15-second refresh',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        if (error != null)
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFFCE2E8),
            child: Text('Data may be stale. $error'),
          ),
        if (loading) const LinearProgressIndicator(),
        if (!loading && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Text('No matching orders.'),
          ),
        for (final order in rows)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    order['receipt'],
                    style: const TextStyle(
                      color: Color(0xFFE32646),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    order['customer_name'],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${order['order_type']} ${order['table_reference'] ?? ''} • ${order['service_status']}',
                  ),
                  Text(
                    '${DateTime.now().difference(DateTime.parse(order['created_at'])).inMinutes} minutes since order',
                  ),
                  const Divider(),
                  for (final line in List<Json>.from(order['lines']))
                    Text(
                      '${line['qty']} × ${line['product_name']}',
                      style: const TextStyle(fontSize: 17),
                    ),
                  if (order['served_at'] != null)
                    Text(
                      'Served by ${order['served_by_name'] ?? order['served_by'] ?? 'Not recorded'}',
                    ),
                  const SizedBox(height: 12),
                  if ([
                    'queued',
                    'preparing',
                    'ready',
                  ].contains(order['service_status']))
                    FilledButton(
                      onPressed: mutating ? null : () => advance(order),
                      child: Text(
                        {
                          'queued': 'Start preparing',
                          'preparing': 'Mark ready',
                          'ready': 'Mark served',
                        }[order['service_status']]!,
                      ),
                    ),
                  if (widget.role == 'admin' &&
                      [
                        'served',
                        'preparing',
                        'ready',
                      ].contains(order['service_status']))
                    TextButton(
                      onPressed: mutating
                          ? null
                          : () => advance(order, reopen: true),
                      child: const Text('Correct / reopen with reason'),
                    ),
                  ExpansionTile(
                    title: const Text('Service history'),
                    children: [
                      for (final event in List<Json>.from(
                        order['events'] ?? [],
                      ))
                        ListTile(
                          title: Text(
                            '${event['action']} → ${event['new_status']}',
                          ),
                          subtitle: Text(
                            '${event['actor_name'] ?? 'Unknown'} • ${event['created_at']}\n${event['reason'] ?? ''}',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
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
                      setState(() => cursors.removeLast());
                      load();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page ${cursors.length}'),
            IconButton(
              tooltip: 'Next page',
              onPressed: rows.length < 10
                  ? null
                  : () {
                      cursors.add({
                        'cursor_time': rows.last['created_at'],
                        'cursor_id': rows.last['id'],
                      });
                      load();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );
}

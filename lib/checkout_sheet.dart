import 'package:flutter/material.dart';
import 'list_controls.dart';
import 'pos_api.dart';

class CheckoutSheet extends StatefulWidget {
  final double total;
  final Future<bool> Function(String customerName)? onComplete;
  final Future<bool> Function(Json payment)? onPayment;
  final Future<bool> Function()? onRecover;
  const CheckoutSheet({
    super.key,
    required this.total,
    this.onComplete,
    this.onPayment,
    this.onRecover,
  });
  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final name = TextEditingController(), table = TextEditingController();
  String amount = '', orderType = 'takeaway';
  String? error;
  bool busy = false, unknown = false;
  int get total => (widget.total * 100).round();
  int get cash => parseMinor(amount) ?? 0;
  bool get ready =>
      cash >= total &&
      name.text.trim().isNotEmpty &&
      !busy &&
      !unknown &&
      (orderType != 'dine-in' || table.text.trim().isNotEmpty);
  @override
  void dispose() {
    name.dispose();
    table.dispose();
    super.dispose();
  }

  void key(String key) {
    if (busy || unknown) return;
    setState(() {
      if (key == '⌫') {
        if (amount.isNotEmpty) amount = amount.substring(0, amount.length - 1);
      } else if (key == '.') {
        if (!amount.contains('.')) amount = '${amount.isEmpty ? '0' : amount}.';
      } else if (amount.length < 10 &&
          (!amount.contains('.') || amount.split('.').last.length < 2)) {
        amount += key;
      }
    });
  }

  Future<void> submit() async {
    if (!ready) return;
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      if (!await confirmAction(
        context,
        title: 'Confirm payment',
        message:
            '${name.text.trim()} • $orderType ${table.text.trim()}\nTotal: ${moneyMinor(total)}\nCash: ${moneyMinor(cash)}\nChange: ${moneyMinor(cash - total)}',
        confirmLabel: 'Confirm sale',
      )) {
        return;
      }
      final success = widget.onPayment != null
          ? await widget.onPayment!({
              'customer_name': name.text.trim(),
              'order_type': orderType,
              'table_reference': table.text.trim(),
              'cash_minor': cash,
              'total_minor': total,
            })
          : await widget.onComplete!(name.text.trim());
      if (mounted && success) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = errorMessage(e);
          unknown = e is! StateError;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> recover() async {
    setState(() => busy = true);
    try {
      if (await widget.onRecover!() && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = errorMessage(e);
          unknown = e is! StateError;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Finish the order',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Close checkout',
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              enabled: !busy && !unknown,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Customer name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            SegmentedButton<String>(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? const Color(0xFFF2DCE1)
                      : states.contains(WidgetState.selected)
                      ? const Color(0xFFE32646)
                      : Colors.white,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? const Color(0xFF82757B)
                      : states.contains(WidgetState.selected)
                      ? Colors.white
                      : const Color(0xFF191519),
                ),
                overlayColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0x1FE32646),
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: Color(0xFFE8CCD4)),
                ),
              ),
              segments: const [
                ButtonSegment(value: 'takeaway', label: Text('Takeaway')),
                ButtonSegment(value: 'dine-in', label: Text('Dine-in')),
              ],
              selected: {orderType},
              onSelectionChanged: busy || unknown
                  ? null
                  : (v) => setState(() => orderType = v.first),
            ),
            if (orderType == 'dine-in')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: table,
                  enabled: !busy && !unknown,
                  maxLength: 40,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Table reference',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Total ${moneyMinor(total)}',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            Text(
              '₱${amount.isEmpty ? '0' : amount}',
              key: const ValueKey('received'),
              style: const TextStyle(fontSize: 26, color: Color(0xFFE32646)),
            ),
            Text(
              cash >= total
                  ? 'Change: ${moneyMinor(cash - total)}'
                  : 'Still needed: ${moneyMinor(total - cash)}',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final value in ['Exact', '200', '500', '1000'])
                  OutlinedButton(
                    onPressed: busy || unknown
                        ? null
                        : () => setState(
                            () => amount = value == 'Exact'
                                ? widget.total.toStringAsFixed(2)
                                : value,
                          ),
                    child: Text(value == 'Exact' ? value : '₱$value'),
                  ),
              ],
            ),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['.', '0', '⌫'],
            ])
              Row(
                children: [
                  for (final value in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: SizedBox(
                          height: 52,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.center,
                              backgroundColor: const Color(0xFFE32646),
                              foregroundColor: Colors.white,
                              overlayColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFF2DCE1),
                              disabledForegroundColor: const Color(0xFF82757B),
                            ),
                            onPressed: busy || unknown
                                ? null
                                : () => key(value),
                            child: Text(
                              value,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                height: 1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Color(0xFFE32646)),
                ),
              ),
            const SizedBox(height: 12),
            if (unknown && widget.onRecover != null)
              FilledButton(
                onPressed: busy ? null : recover,
                child: Text(
                  busy ? 'Checking…' : 'Check saved result / retry safely',
                ),
              )
            else
              FilledButton(
                onPressed: ready ? submit : null,
                child: Text(busy ? 'Saving order…' : 'Complete sale'),
              ),
          ],
        ),
      ),
    ),
  );
}

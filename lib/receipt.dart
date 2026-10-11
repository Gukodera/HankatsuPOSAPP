import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pos_api.dart';
import 'export_file.dart';
import 'sale_success.dart';
import 'pdf_export.dart';
import 'export_notice.dart';

String receiptText(Json receipt) {
  final lines = List<Json>.from(receipt['lines'] as List? ?? []);
  return [
    'HANKATSU',
    'Sales receipt ${receipt['receipt']}',
    receipt['customer_name'],
    '${receipt['order_type']} ${receipt['table_reference'] ?? ''}',
    'Date: ${receipt['created_at']}',
    'Cashier: ${receipt['cashier_name'] ?? 'Not recorded'}',
    'Payment: ${receipt['payment_status']} • Service: ${receipt['service_status']}',
    for (final l in lines)
      '${l['qty']} × ${l['product_name']} • Unit ${l['unit_minor'] == null ? 'unknown' : moneyMinor(l['unit_minor'])} • ${l['line_minor'] == null ? 'amount not recorded' : moneyMinor(l['line_minor'])}',
    'Total: ${moneyMinor(receipt['total_minor'])}',
    if (receipt['cash_minor'] != null)
      'Cash: ${moneyMinor(receipt['cash_minor'])}',
    if (receipt['change_minor'] != null)
      'Change: ${moneyMinor(receipt['change_minor'])}',
    if (receipt['reversal_reason'] != null)
      'Correction: ${receipt['reversal_reason']}',
    'Tax breakdown: not configured',
  ].join('\n');
}

Future<void> showReceipt(
  BuildContext context,
  Json receipt, {
  bool celebrate = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (celebrate) const SaleSuccess(),
          const Text(
            'Sales receipt',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          SelectableText(receiptText(receipt)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: receiptText(receipt)),
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('Receipt copied')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy receipt'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final message = await exportBytes(
                  '${receipt['receipt'].toString().replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '_')}.pdf',
                  () => receiptPdf(receipt),
                  'application/pdf',
                );
                if (ctx.mounted) {
                  showExportNotice(ctx, message);
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                }
              }
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Export receipt (PDF)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  ),
);

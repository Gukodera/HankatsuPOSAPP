import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/pdf_export.dart';
import 'package:hankatsu/pos_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final receipt = <String, dynamic>{
    'receipt': 'HK-PDF-001',
    'customer_name': 'José Dela Cruz',
    'created_at': '2026-10-05T04:30:00Z',
    'cashier_name': 'María',
    'order_type': 'dine-in',
    'table_reference': 'Table 8',
    'payment_status': 'paid',
    'service_status': 'queued',
    'total_minor': 35000,
    'cash_minor': 50000,
    'change_minor': 15000,
    'lines': [
      {
        'product_name': 'Chicken Katsu with rice',
        'qty': 2,
        'unit_minor': 15000,
        'line_minor': 30000,
      },
      {
        'product_name': 'Iced tea',
        'qty': 1,
        'unit_minor': 5000,
        'line_minor': 5000,
      },
    ],
  };

  test('Receipt and summary exports are actual PDF documents', () async {
    final dir = Directory('tmp/pdfs')..createSync(recursive: true);
    final documents = {
      'receipt': await receiptPdf(receipt),
      'summary': await periodSummaryPdf(
        'HANKATSU DAILY SUMMARY\nStore • Asia/Manila\n2026-10-05\nTransactions: 2\nGross: ₱350.00\nReversals recorded this period: ₱0.00\nNet: ₱350.00',
      ),
      'long-receipt': await receiptPdf({
        ...receipt,
        'total_minor': 1800000,
        'cash_minor': 1800000,
        'change_minor': 0,
        'lines': [
          for (var i = 1; i <= 120; i++)
            <String, dynamic>{
              'product_name':
                  'Item $i - Chicken Katsu with rice and a long description',
              'qty': 1,
              'unit_minor': 15000,
              'line_minor': 15000,
            },
        ],
      }),
      'legacy-receipt': await receiptPdf(<String, dynamic>{
        'receipt': 'HK-LEGACY',
        'total_minor': 10000,
        'reversal_reason': 'Customer requested cancellation',
        'lines': <Json>[
          {'product_name': 'Katsu', 'qty': 1},
        ],
      }),
    };
    for (final entry in documents.entries) {
      expect(ascii.decode(entry.value.take(5).toList()), '%PDF-');
      expect(entry.value.length, greaterThan(1000));
      File('${dir.path}/${entry.key}.pdf').writeAsBytesSync(entry.value);
    }
  });
}

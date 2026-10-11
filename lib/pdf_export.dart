import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pos_api.dart';

final _red = PdfColor.fromHex('#E32646');
final _pink = PdfColor.fromHex('#FCE2E8');
final _ink = PdfColor.fromHex('#191519');
final _muted = PdfColor.fromHex('#82757B');

Future<Uint8List> _document(String title, List<pw.Widget> content) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final pdf = pw.Document(title: title, author: 'Hankatsu POS');
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      maxPages: 200,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (_) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 20),
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _red, width: 2)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'HANKATSU',
              style: pw.TextStyle(
                color: _red,
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(title, style: pw.TextStyle(color: _ink, fontSize: 13)),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 16),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Hankatsu POS',
              style: pw.TextStyle(fontSize: 9, color: _muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
      ),
      build: (_) => content,
    ),
  );
  return pdf.save();
}

pw.Widget _detail(String label, dynamic value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Text(
    '$label: ${value ?? "Not recorded"}',
    style: pw.TextStyle(fontSize: 10, color: _ink),
  ),
);

Future<Uint8List> receiptPdf(Json receipt) {
  final lines = List<Json>.from(receipt['lines'] ?? []);
  String money(dynamic value) =>
      value == null ? 'Not recorded' : moneyMinor((value as num).toInt());
  return _document('Sales receipt', [
    _detail('Receipt', receipt['receipt']),
    _detail('Customer', receipt['customer_name']),
    _detail('Date', receipt['created_at']),
    _detail('Cashier', receipt['cashier_name']),
    _detail(
      'Order',
      '${receipt["order_type"] ?? "Not recorded"}${receipt["table_reference"] == null ? "" : " - ${receipt["table_reference"]}"}',
    ),
    _detail('Payment', receipt['payment_status']),
    _detail('Service', receipt['service_status']),
    pw.SizedBox(height: 12),
    pw.TableHelper.fromTextArray(
      headers: ['Item', 'Qty', 'Unit price', 'Amount'],
      data: [
        for (final line in lines)
          [
            '${line["product_name"]}',
            '${line["qty"]}',
            money(line['unit_minor']),
            money(line['line_minor']),
          ],
      ],
      border: null,
      headerDecoration: pw.BoxDecoration(color: _pink),
      headerStyle: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
      cellStyle: pw.TextStyle(fontSize: 10, color: _ink),
      cellPadding: const pw.EdgeInsets.all(8),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
    ),
    pw.SizedBox(height: 16),
    pw.Text(
      'Total: ${money(receipt["total_minor"])}',
      style: pw.TextStyle(
        fontSize: 20,
        color: _red,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
    pw.SizedBox(height: 8),
    if (receipt['cash_minor'] != null)
      _detail('Cash', money(receipt['cash_minor'])),
    if (receipt['change_minor'] != null)
      _detail('Change', money(receipt['change_minor'])),
    if (receipt['reversal_reason'] != null)
      _detail('Correction', receipt['reversal_reason']),
    pw.SizedBox(height: 8),
    _detail('Tax breakdown', 'Not configured'),
  ]);
}

Future<Uint8List> periodSummaryPdf(String text) => _document('Period summary', [
  for (final line in text.split('\n'))
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Text(line, style: pw.TextStyle(fontSize: 12, color: _ink)),
    ),
]);

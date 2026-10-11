import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/analytics_page.dart';
import 'package:hankatsu/pos_api.dart';

class ReportsFake extends PosApi {
  final calls = <String>[];
  @override
  Future<dynamic> call(String action, [Json args = const {}]) async {
    calls.add(action);
    if (action == 'report') {
      return {
        'as_of': '2026-09-30T10:00:00Z',
        'gross_minor': 25000,
        'reversal_minor': 0,
        'net_minor': 25000,
        'count': 12,
        'best': [],
        'buckets': [],
        'scope': 'Store',
        'start': '2026-09-29T16:00:00Z',
        'end': '2026-09-30T16:00:00Z',
      };
    }
    if (action == 'invoices') {
      return {
        'rows': [
          for (
            var i = args.containsKey('cursor_id') ? 10 : 0;
            i < (args.containsKey('cursor_id') ? 12 : 10);
            i++
          )
            {
              'id': 'i$i',
              'receipt': 'HK-$i',
              'customer_name': 'Customer $i',
              'created_at': '2026-09-30T10:00:00Z',
              'total_minor': 25000,
              'payment_status': 'paid',
            },
        ],
        'count': 12,
      };
    }
    return {};
  }
}

void main() {
  test('Manila calendar period boundaries handle leap and year rollover', () {
    expect(periodStart(DateTime(2026, 1, 1), 'weekly'), DateTime(2025, 12, 29));
    expect(
      shiftPeriod(DateTime(2026, 12, 31), 'monthly', 1),
      DateTime(2027, 1, 1),
    );
    expect(
      shiftPeriod(DateTime(2024, 2, 29), 'monthly', 1),
      DateTime(2024, 3, 1),
    );
  });
  testWidgets('Invoice archive requests only the selected page', (
    tester,
  ) async {
    final api = ReportsFake();
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyticsPage(
          api: api,
          staff: const {'role': 'cashier', 'business_date': '2026-09-30'},
          invoicesOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c == 'invoices').length, 1);
    await tester.scrollUntilVisible(
      find.byTooltip('Next page'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c == 'invoices').length, 2);
    expect(find.text('Page 2'), findsOneWidget);
  });
}

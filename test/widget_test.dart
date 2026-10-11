import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/orders_page.dart';
import 'package:hankatsu/pos_api.dart';

class OrdersFake extends PosApi {
  int writes = 0;
  bool fail = false;
  String status = 'queued';
  @override
  Future<dynamic> call(String action, [Json args = const {}]) async {
    if (action == 'transition') {
      if (fail) throw StateError('Order changed. Refresh before continuing');
      writes++;
      status = args['target'];
      return {};
    }
    return {
      'count': status == args['status'] ? 1 : 0,
      'refreshed_at': '2026-09-30T10:00:00Z',
      'rows': [
        if (status == args['status'])
          {
            'id': 'one',
            'receipt': 'HK-0001',
            'customer_name': 'Maria',
            'service_status': status,
            'order_type': 'takeaway',
            'created_at': '2026-09-30T09:50:00Z',
            'lines': [
              {'product_name': 'Katsu', 'qty': 2},
            ],
            'events': [],
          },
      ],
    };
  }
}

void main() {
  testWidgets('Service transition requires confirmation', (tester) async {
    final api = OrdersFake();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrdersPage(api: api, role: 'kitchen'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Start preparing'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start preparing'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    expect(api.status, 'preparing');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Failed transition leaves the ticket available', (tester) async {
    final api = OrdersFake()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OrdersPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Start preparing'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start preparing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    expect(api.status, 'queued');
    await tester.pumpWidget(const SizedBox());
  });
}

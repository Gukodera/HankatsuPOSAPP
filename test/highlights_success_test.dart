import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/pos_api.dart';
import 'package:hankatsu/today_highlights.dart';
import 'package:hankatsu/receipt.dart';

class HighlightsApi extends PosApi {
  bool empty = false, fail = false;
  final requests = <Json>[];
  @override
  Future<dynamic> call(String action, [Json args = const {}]) async {
    requests.add(args);
    if (fail) throw StateError('Offline');
    return {
      'scope': 'My sales',
      'date': '2026-10-05',
      'net_minor': empty ? 0 : 12500,
      'count': empty ? 0 : 2,
      'best': empty
          ? []
          : [
              {'product_name': 'Katsu', 'qty': 3},
            ],
      'buckets': empty
          ? []
          : [
              {'bucket': '12', 'total_minor': 12500},
            ],
    };
  }
}

void main() {
  testWidgets(
    'Highlights use server business day, refresh and handle empty/offline states',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = HighlightsApi();
      Widget page(int refresh) => MaterialApp(
        home: Scaffold(
          body: TodayHighlights(api: api, refresh: refresh),
        ),
      );
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      expect(api.requests.single, {'period': 'daily'});
      expect(find.text('Best seller: Katsu • 3 sold'), findsOneWidget);
      expect(find.text('₱125.00'), findsOneWidget);
      api.empty = true;
      await tester.pumpWidget(page(1));
      await tester.pumpAndSettle();
      expect(find.text('Your first sale starts the story.'), findsOneWidget);
      api.fail = true;
      await tester.tap(find.byTooltip('Refresh highlights'));
      await tester.pumpAndSettle();
      expect(
        find.text('Highlights unavailable. Tap refresh to try again.'),
        findsOneWidget,
      );
      expect(find.text('₱0.00'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Only a newly completed sale celebrates in its receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showReceipt(context, {
                    'lines': [],
                    'total_minor': 10000,
                  }, celebrate: true),
                  child: const Text('New sale'),
                ),
                TextButton(
                  onPressed: () =>
                      showReceipt(context, {'lines': [], 'total_minor': 10000}),
                  child: const Text('Archive'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('New sale'));
    await tester.pumpAndSettle();
    expect(find.text('Sale complete!'), findsOneWidget);
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Sale complete!'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

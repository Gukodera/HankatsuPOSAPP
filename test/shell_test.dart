import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hankatsu/main.dart';
import 'package:hankatsu/pos_api.dart';

class ShellApi extends PosApi {
  @override
  Future<dynamic> call(String action, [Json args = const {}]) async {
    if (action == 'catalog') {
      return (args['offset'] ?? 0) > 0
          ? []
          : [
              {
                'id': 'p1',
                'name': 'Katsu',
                'category': 'Meals',
                'price': 100,
                'stock': 5,
              },
            ];
    }
    if (action == 'shift') return null;
    if (action == 'report') {
      return {
        'as_of': '2026-09-30T10:00:00Z',
        'gross_minor': 0,
        'reversal_minor': 0,
        'net_minor': 0,
        'count': 0,
        'best': [],
        'buckets': [],
        'scope': 'My sales',
      };
    }
    return [];
  }
}

void main() {
  testWidgets(
    'Refresh preserves one cart line and logout cancellation preserves draft',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Shell(
            api: ShellApi(),
            staff: const {
              'role': 'cashier',
              'name': 'Test cashier',
              'business_date': '2026-09-30',
            },
            userId: 'test-cashier',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Add one'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Refresh menu'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh menu'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Add one'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      final draft = await DraftStore('test-cashier').read();
      expect(draft['cart'].length, 1);
      expect(draft['cart'][0]['qty'], 2);
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await DraftStore('test-cashier').read())['cart'][0]['qty'], 2);
      expect(tester.takeException(), isNull);
    },
  );
}

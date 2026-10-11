import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/checkout_sheet.dart';

void main() {
  for (final width in [360.0, 800.0]) {
    testWidgets(
      'Zero key works and checkout requires a customer at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? savedName;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            home: Scaffold(
              body: CheckoutSheet(
                total: 100,
                onComplete: (name) async {
                  savedName = name;
                  return false;
                },
              ),
            ),
          ),
        );
        for (final key in ['1', '0', '0']) {
          await tester.ensureVisible(find.text(key));
          final labelRect = tester.getRect(find.text(key));
          final keyRect = tester.getRect(
            find.widgetWithText(FilledButton, key),
          );
          expect((labelRect.center - keyRect.center).distance, lessThan(1));
          expect(keyRect.contains(labelRect.topLeft), isTrue);
          expect(keyRect.contains(labelRect.bottomRight), isTrue);
          await tester.tap(find.text(key));
          await tester.pump();
        }
        expect(find.text('₱100'), findsOneWidget);
        var button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Complete sale'),
        );
        expect(button.onPressed, isNull);
        await tester.enterText(find.byType(TextField), '  Maria  ');
        await tester.pump();
        await tester.ensureVisible(find.text('Complete sale'));
        await tester.tap(find.text('Complete sale'));
        await tester.pumpAndSettle();
        expect(savedName, isNull);
        expect(find.text('Confirm payment'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(savedName, isNull);
        await tester.tap(find.text('Complete sale'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm sale'));
        await tester.pumpAndSettle();
        expect(savedName, 'Maria');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/main.dart';

void main() {
  testWidgets('Login fits small screens and can reveal the password', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();
    final password = find.byType(TextField).last;
    await tester.ensureVisible(password);
    await tester.enterText(password, 'sample-password');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    expect(
      tester.widget<TextField>(password).controller!.text,
      'sample-password',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

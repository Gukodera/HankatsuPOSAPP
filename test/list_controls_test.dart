import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/list_controls.dart';

void main() {
  test('Ten rows per page and page clamps after filtering', () {
    final rows = List.generate(23, (i) => i);
    expect(PageSlice(rows, 0).rows, List.generate(10, (i) => i));
    expect(PageSlice(rows, 1).rows, List.generate(10, (i) => i + 10));
    expect(PageSlice(rows, 2).rows, [20, 21, 22]);
    expect(PageSlice(rows.take(2).toList(), 2).page, 0);
    expect(const PageSlice<int>([], 4).rows, isEmpty);
  });
  testWidgets('Pagination only appears beyond ten records', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaginationBar(
            count: 10,
            page: 0,
            onChanged: (p) => selected = p,
          ),
        ),
      ),
    );
    expect(find.byTooltip('Next page'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaginationBar(
            count: 11,
            page: 0,
            onChanged: (p) => selected = p,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Next page'));
    expect(selected, 1);
  });
  testWidgets('Confirmation cancel and accept return the chosen result', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmAction(
                  context,
                  title: 'Sign out?',
                  message: 'Discard the unfinished cart?',
                  confirmLabel: 'Sign out',
                );
              },
              child: const Text('Logout'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, false);
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(result, true);
  });
}

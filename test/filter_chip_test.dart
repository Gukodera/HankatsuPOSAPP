import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/filter_chip.dart';

void main() {
  testWidgets('Selected filters use red with white text and checkmarks', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, update) => PosFilterChip(
              label: 'Available',
              selected: selected,
              onSelected: (value) => update(() => selected = value),
            ),
          ),
        ),
      ),
    );
    var chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.labelStyle?.color, const Color(0xFF191519));
    await tester.tap(find.text('Available'));
    await tester.pumpAndSettle();
    chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.selected, true);
    expect(chip.selectedColor, const Color(0xFFE32646));
    expect(chip.labelStyle?.color, Colors.white);
    expect(chip.checkmarkColor, Colors.white);
  });
}

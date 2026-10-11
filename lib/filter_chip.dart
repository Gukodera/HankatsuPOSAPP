import 'package:flutter/material.dart';

class PosFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  const PosFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: onSelected,
    selectedColor: const Color(0xFFE32646),
    backgroundColor: Colors.white,
    labelStyle: TextStyle(
      color: selected ? Colors.white : const Color(0xFF191519),
      fontWeight: FontWeight.w700,
    ),
    checkmarkColor: Colors.white,
    side: BorderSide(
      color: selected ? const Color(0xFFE32646) : const Color(0xFFE8CCD4),
    ),
  );
}

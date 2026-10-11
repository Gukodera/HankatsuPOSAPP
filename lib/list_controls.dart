import 'package:flutter/material.dart';

class PageSlice<T> {
  final List<T> all;
  final int requested;
  static const size = 10;
  const PageSlice(this.all, this.requested);
  int get pages => ((all.length + size - 1) ~/ size).clamp(1, 100000000);
  int get page => requested.clamp(0, pages - 1);
  List<T> get rows => all.skip(page * size).take(size).toList();
}

class PaginationBar extends StatelessWidget {
  final int count, page;
  final ValueChanged<int> onChanged;
  const PaginationBar({
    super.key,
    required this.count,
    required this.page,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final pages = ((count + 9) ~/ 10).clamp(1, 100000000);
    final current = page.clamp(0, pages - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            count == 0
                ? '0 results'
                : '${current * 10 + 1}–${((current + 1) * 10).clamp(0, count)} of $count',
            style: const TextStyle(color: Color(0xFF82757B), fontSize: 12),
          ),
          if (count > 10)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: current > 0 ? () => onChanged(current - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${current + 1} / $pages'),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: current + 1 < pages
                      ? () => onChanged(current + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

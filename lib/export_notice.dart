import 'package:flutter/material.dart';

void showExportNotice(BuildContext context, String? message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFFFCE2E8),
      duration: const Duration(seconds: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Row(
        children: [
          Icon(
            message == null
                ? Icons.close_rounded
                : message.startsWith('Download started')
                ? Icons.download_rounded
                : Icons.check_circle_outline,
            color: const Color(0xFFE32646),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message ?? 'Export canceled. No file was saved.',
              style: const TextStyle(color: Color(0xFF191519)),
            ),
          ),
        ],
      ),
      action: SnackBarAction(
        label: 'Dismiss',
        textColor: const Color(0xFFE32646),
        onPressed: messenger.hideCurrentSnackBar,
      ),
    ),
  );
}

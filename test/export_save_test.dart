import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/export_native.dart';
import 'package:hankatsu/export_notice.dart';

class SavePicker extends FilePickerPlatform {
  final completed = Completer<Uri?>();
  Uint8List? savedBytes;
  String? suggestedName, savedMime;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    suggestedName = fileName;
    savedBytes = bytes;
    savedMime = mimeType;
    return completed.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SavePicker picker;
  late FilePickerPlatform original;
  setUp(() {
    original = FilePickerPlatform.instance;
    picker = SavePicker();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() => FilePickerPlatform.instance = original);

  testWidgets(
    'CSV confirmation waits for save and shows the chosen destination',
    (tester) async {
      picker = SavePicker();
      FilePickerPlatform.instance = picker;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final result = await exportFile(
                    'sales.csv',
                    () async => 'Customer,Total\nJosé,350',
                    'text/csv',
                  );
                  if (context.mounted) showExportNotice(context, result);
                },
                child: const Text('Export CSV'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Export CSV'));
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(picker.suggestedName, 'sales.csv');
      expect(picker.savedMime, 'text/csv');
      expect(utf8.decode(picker.savedBytes!), contains('José'));
      picker.completed.complete(
        Uri.file('D:/ChosenFolder/sales.csv', windows: true),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ChosenFolder'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    },
  );

  test(
    'Cancel returns no success message and write failures are propagated',
    () async {
      final result = exportBytes(
        'receipt.pdf',
        () async => Uint8List.fromList([37, 80, 68, 70]),
        'application/pdf',
      );
      picker.completed.complete(null);
      expect(await result, isNull);
      picker = SavePicker();
      FilePickerPlatform.instance = picker;
      final failed = exportBytes(
        'receipt.pdf',
        () async => Uint8List.fromList([37, 80, 68, 70]),
        'application/pdf',
      );
      final check = expectLater(failed, throwsStateError);
      picker.completed.completeError(StateError('Disk full'));
      await check;
    },
  );
}

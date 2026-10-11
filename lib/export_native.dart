import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<String?> exportFile(
  String name,
  Future<String> Function() build,
  String mime,
) => exportBytes(
  name,
  () async => Uint8List.fromList(utf8.encode(await build())),
  mime,
);

Future<String?> exportBytes(
  String name,
  Future<Uint8List> Function() build,
  String mime,
) async {
  final bytes = await build();
  final saved = await FilePicker.saveFile(
    fileName: name,
    bytes: bytes,
    mimeType: mime,
    dialogTitle: 'Save ${name.endsWith(".pdf") ? "PDF" : "CSV"} export',
  );
  if (saved == null) return null;
  final destination = saved.scheme == 'file'
      ? saved.toFilePath(windows: Platform.isWindows)
      : Uri.decodeFull(saved.toString());
  return 'Saved successfully to\n$destination';
}

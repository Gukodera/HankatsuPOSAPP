// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';

@JS('window.showSaveFilePicker')
external JSFunction? get _savePicker;

extension type _SaveHandle(JSObject _) implements JSObject {
  external String get name;
  external JSPromise<_SaveWriter> createWritable();
}

extension type _SaveWriter(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array bytes);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> abort();
}

extension type _SaveError(JSObject _) implements JSObject {
  external String get name;
}

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
  final picker = _savePicker;
  if (picker != null) {
    _SaveHandle handle;
    try {
      // Open synchronously from the tap, before fetching data or generating PDF.
      handle =
          await (picker.callAsFunction(
                    globalContext,
                    {
                      'suggestedName': name,
                      'types': [
                        {
                          'description': name.endsWith('.pdf')
                              ? 'PDF document'
                              : 'CSV spreadsheet',
                          'accept': {
                            mime: ['.${name.split('.').last}'],
                          },
                        },
                      ],
                    }.jsify(),
                  )
                  as JSPromise<_SaveHandle>)
              .toDart;
    } catch (e) {
      try {
        if (_SaveError(e as JSObject).name == 'AbortError') return null;
      } catch (_) {
        /* Non-DOM errors still propagate. */
      }
      rethrow;
    }
    final content = await build();
    final writer = await handle.createWritable().toDart;
    try {
      await writer.write(content.toJS).toDart;
      await writer.close().toDart;
    } catch (_) {
      try {
        await writer.abort().toDart;
      } catch (_) {
        /* Preserve the original save error. */
      }
      rethrow;
    }
    return 'Saved ${handle.name} to the folder you selected.';
  }
  final content = await build();
  final blob = html.Blob([content], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)..download = name;
  html.document.body?.append(a);
  a.click();
  a.remove();
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => html.Url.revokeObjectUrl(url),
  );
  return 'Download started: $name\nYour browser controls the save location. Check Downloads to confirm it finished.';
}

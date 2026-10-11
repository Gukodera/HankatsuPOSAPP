@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankatsu/export_web.dart';

@JS('window.showSaveFilePicker')
external JSFunction? get savePicker;
@JS('window.showSaveFilePicker')
external set savePicker(JSFunction? value);

@JS('Promise.reject')
external JSPromise<JSAny?> rejectPromise(JSAny? reason);

void main() {
  JSFunction? original;
  setUp(() => original = savePicker);
  tearDown(() => savePicker = original);

  test(
    'Browser picker precedes generation and confirms only after close',
    () async {
      var opened = false;
      Uint8List? written;
      final writeStarted = Completer<void>();
      final closed = Completer<JSAny?>();
      final writer = <String, Object?>{}.jsify() as JSObject;
      writer.setProperty(
        'write'.toJS,
        ((JSUint8Array data) {
          written = data.toDart;
          writeStarted.complete();
          return Future<JSAny?>.value(null).toJS;
        }).toJS,
      );
      writer.setProperty('close'.toJS, (() => closed.future.toJS).toJS);
      final handle = {'name': 'chosen.csv'}.jsify() as JSObject;
      handle.setProperty(
        'createWritable'.toJS,
        (() => Future<JSObject>.value(writer).toJS).toJS,
      );
      savePicker = ((JSObject options) {
        expect(
          options.getProperty<JSString>('suggestedName'.toJS).toDart,
          'sales.csv',
        );
        opened = true;
        return Future<JSObject>.value(handle).toJS;
      }).toJS;
      var complete = false;
      final result =
          exportFile('sales.csv', () async {
            expect(opened, isTrue);
            return 'Customer,Total\nJosé,350';
          }, 'text/csv').then((value) {
            complete = true;
            return value;
          });
      await Future.any<void>([
        writeStarted.future,
        result.then((_) => throw StateError('Export finished before close')),
      ]);
      expect(utf8.decode(written!), contains('José'));
      expect(complete, isFalse);
      closed.complete(null);
      expect(await result, 'Saved chosen.csv to the folder you selected.');
    },
  );

  test('Browser cancellation skips generation', () async {
    savePicker = ((JSObject _) => rejectPromise(
      {'name': 'AbortError'}.jsify(),
    )).toJS;
    var generated = false;
    expect(
      await exportBytes('receipt.pdf', () async {
        generated = true;
        return Uint8List.fromList([37, 80, 68, 70]);
      }, 'application/pdf'),
      isNull,
    );
    expect(generated, isFalse);
  });

  test(
    'Browser write failure aborts and never returns a success message',
    () async {
      var aborted = false;
      final writer = <String, Object?>{}.jsify() as JSObject;
      writer.setProperty(
        'write'.toJS,
        ((JSUint8Array _) => rejectPromise(
          {'name': 'QuotaExceededError'}.jsify(),
        )).toJS,
      );
      writer.setProperty(
        'abort'.toJS,
        (() {
          aborted = true;
          return Future<JSAny?>.value(null).toJS;
        }).toJS,
      );
      final handle = {'name': 'receipt.pdf'}.jsify() as JSObject;
      handle.setProperty(
        'createWritable'.toJS,
        (() => Future<JSObject>.value(writer).toJS).toJS,
      );
      savePicker = ((JSObject _) => Future<JSObject>.value(handle).toJS).toJS;
      await expectLater(
        exportBytes(
          'receipt.pdf',
          () async => Uint8List.fromList([37, 80, 68, 70]),
          'application/pdf',
        ),
        throwsA(anything),
      );
      expect(aborted, isTrue);
    },
  );
}

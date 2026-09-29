// Web-only file picker. Loaded through a conditional import.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../domain/media_picker.dart';

/// Opens the browser's file dialog through an `<input type="file">` element
/// and reads the chosen file into memory.
class PlatformMediaPicker implements MediaPicker {
  @override
  Future<PickedMedia?> pick({String accept = ''}) {
    final done = Completer<PickedMedia?>();
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..accept = accept;
    input.style.display = 'none';
    web.document.body!.append(input);

    void finish(PickedMedia? result) {
      if (!done.isCompleted) done.complete(result);
      input.remove();
    }

    Future<void> read() async {
      final files = input.files;
      if (files == null || files.length == 0) {
        finish(null);
        return;
      }
      final file = files.item(0)!;
      try {
        final buffer = await file.arrayBuffer().toDart;
        finish(PickedMedia(
          name: file.name,
          bytes: buffer.toDart.asUint8List(),
          contentType: file.type,
        ));
      } catch (_) {
        finish(null);
      }
    }

    // The listener itself must not return a Future.
    input.addEventListener('change', ((web.Event _) {
      unawaited(read());
    }).toJS);
    input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
    input.click();
    return done.future;
  }
}

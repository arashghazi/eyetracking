// Web-only download helper. Loaded through a conditional import.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Offers [bytes] to the person as a download: a Blob behind a temporary
/// `<a download>` link that is clicked and removed again.
Future<bool> saveFile(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  anchor.style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Some browsers read the link a moment after the click; free it later.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return true;
}

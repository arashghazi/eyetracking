import 'dart:typed_data';

/// Outside the browser there is no download yet: nothing is saved.
Future<bool> saveFile(Uint8List bytes, String filename, String mimeType) async =>
    false;

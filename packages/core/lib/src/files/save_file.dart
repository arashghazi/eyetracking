import 'dart:typed_data';

/// Hands [bytes] to the person as a file called [filename]. Returns true
/// when the file was offered for download (the browser decides where it
/// goes), false when this platform cannot save files.
///
/// Screens receive this as a dependency (`FileSaver`) so tests can record
/// what would have been saved.
typedef FileSaver = Future<bool> Function(
  Uint8List bytes,
  String filename,
  String mimeType,
);

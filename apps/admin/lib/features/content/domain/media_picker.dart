import 'dart:typed_data';

/// A file the researcher picked.
class PickedMedia {
  const PickedMedia({
    required this.name,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;

  /// The browser's media type for the file (may be empty).
  final String contentType;
}

/// Port for choosing a file on the researcher's computer. The browser build
/// opens a file dialog; other platforms cannot yet.
abstract class MediaPicker {
  /// Opens the file dialog; null when it was cancelled or is unavailable.
  /// [accept] is a comma-separated list of media types or extensions.
  Future<PickedMedia?> pick({String accept = ''});
}

/// The media types the server accepts (video/webm, video/mp4, image/png,
/// image/jpeg).
const String kAcceptedMedia = 'video/webm,video/mp4,image/png,image/jpeg';

/// Media type for a file name when the browser did not report one.
String mediaTypeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

/// The media key reported with a `media_start` event.
///
/// The signed link of a clip does not always contain the key of the file:
/// the service issues `/media/<token>`, where the key is inside the token.
/// The key is taken from the link when the link carries it, as the last path
/// part before the token (`/media/<key>/<token>`, or `/<path>/<key>?token=`);
/// otherwise the segment id stands in for it.
String mediaKeyFromUrl(String url, String segmentId) {
  final uri = Uri.tryParse(url);
  if (uri == null) return segmentId;
  final parts = [
    for (final p in uri.pathSegments)
      if (p.isNotEmpty) p,
  ];
  String? key;
  if (uri.queryParameters.containsKey('token')) {
    // The token travels in the query: the file is the last path part.
    key = parts.isEmpty ? null : parts.last;
  } else if (parts.length >= 3) {
    // The token is the last path part: the key is the one before it.
    key = parts[parts.length - 2];
  }
  if (key == null || key.isEmpty || key == 'media') return segmentId;
  return key;
}

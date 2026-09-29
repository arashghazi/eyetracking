/// Error raised for any failed API call.
///
/// [message] is safe to show to the user: it is the server's `detail` text
/// or a short generic sentence when the server could not be reached.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.body});

  final String message;

  /// HTTP status, or null when no response arrived (network failure).
  final int? statusCode;

  /// The decoded JSON error body, when there was one.
  final Object? body;

  /// Media keys the server reports as missing (`missing_media`, at the top of
  /// the body or inside `detail`, or listed in the message as
  /// `missing media: a.webm, b.webm`), for example when approving content.
  List<String> get missingMedia {
    List<String> from(Object? map) => map is Map && map['missing_media'] is List
        ? [for (final k in map['missing_media'] as List) '$k']
        : const [];
    final b = body;
    final top = from(b);
    if (top.isNotEmpty) return top;
    final nested = b is Map ? from(b['detail']) : const <String>[];
    if (nested.isNotEmpty) return nested;
    // The message itself may list them: "missing media: a.webm, b.webm".
    final match = RegExp(r'^missing media:\s*(.+)$', caseSensitive: false)
        .firstMatch(message.trim());
    return match == null
        ? const []
        : [
            for (final k in match.group(1)!.split(','))
              if (k.trim().isNotEmpty) k.trim(),
          ];
  }

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

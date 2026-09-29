/// Error raised for any failed API call.
///
/// [message] is safe to show to the user: it is the server's `detail` text
/// or a short generic sentence when the server could not be reached.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// HTTP status, or null when no response arrived (network failure).
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

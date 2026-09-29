import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_store.dart';

/// Thin JSON-over-HTTP client for the EyeTracking service.
///
/// Adds the bearer token from [tokenStore], decodes JSON and converts every
/// failure into an [ApiException] whose message can be shown to the user.
class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? httpClient,
    TokenStore? tokenStore,
    this.onUnauthorized,
    this.timeout = const Duration(seconds: 20),
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        tokenStore = tokenStore ?? TokenStore(),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final TokenStore tokenStore;
  final Duration timeout;

  /// Called when a request that carried a token is answered with 401, i.e. the
  /// session has expired. Not called for failed sign-ins (no token yet).
  final void Function()? onUnauthorized;

  final http.Client _http;

  /// GET. With [nullOn404] a missing resource yields null instead of an error.
  Future<Object?> get(String path, {bool nullOn404 = false}) =>
      _send('GET', path, nullOn404: nullOn404);

  Future<Object?> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<Object?> put(String path, [Object? body]) =>
      _send('PUT', path, body: body);

  /// Convenience: response must be a JSON object.
  Future<Map<String, dynamic>> getObject(String path) async =>
      _asObject(await get(path));

  Future<Map<String, dynamic>?> getObjectOrNull(String path) async {
    final value = await get(path, nullOn404: true);
    return value == null ? null : _asObject(value);
  }

  Future<List<dynamic>> getList(String path) async {
    final value = await get(path);
    if (value is List) return value;
    throw const ApiException('The server sent an unexpected response.');
  }

  Future<Map<String, dynamic>> postObject(String path, [Object? body]) async =>
      _asObject(await post(path, body));

  Future<Map<String, dynamic>> putObject(String path, [Object? body]) async =>
      _asObject(await put(path, body));

  /// Makes a path the server sent (such as the signed `/media/<token>` of a
  /// video) reachable from the browser: a root-relative path is joined to
  /// the service address, because the app is served from another origin.
  /// Absolute URLs are returned untouched, exactly as signed.
  String resolveUrl(String url) =>
      url.startsWith('/') && !url.startsWith('//') ? '$baseUrl$url' : url;

  /// Uploads [bytes] as the multipart field [field]. [onProgress] receives
  /// the bytes handed to the HTTP client and the total; in a browser the
  /// client sends after it has read everything, so this shows preparation
  /// rather than network progress.
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    String field = 'file',
    void Function(int sent, int total)? onProgress,
  }) async {
    final token = tokenStore.token;
    // Hand-built multipart body: this keeps the package free of extra
    // dependencies and lets us count the bytes as they are handed over.
    final boundary = 'et-${DateTime.now().microsecondsSinceEpoch}';
    final safeName = filename.replaceAll(RegExp(r'["\r\n]'), '_');
    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="$field"; filename="$safeName"\r\n'
        'Content-Type: $contentType\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final total = head.length + bytes.length + tail.length;
    final request = http.StreamedRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'multipart/form-data; boundary=$boundary'
      ..headers['Accept'] = 'application/json'
      ..contentLength = total;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    unawaited(() async {
      var sent = 0;
      void add(List<int> chunk) {
        request.sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent, total);
      }

      add(head);
      const chunkSize = 64 * 1024;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        add(bytes.sublist(i, math.min(i + chunkSize, bytes.length)));
        await Future<void>.delayed(Duration.zero);
      }
      add(tail);
      await request.sink.close();
    }());
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(minutes: 10)),
      );
    } on TimeoutException {
      throw const ApiException(
        'The upload took too long. Check the connection and try again.',
      );
    } on Exception {
      throw const ApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
    final decoded = _decode(response);
    final status = response.statusCode;
    if (status >= 200 && status < 300) return _asObject(decoded);
    if (status == 401 && token != null) onUnauthorized?.call();
    throw ApiException(
      _errorMessage(status, decoded),
      statusCode: status,
      body: decoded,
    );
  }

  void close() => _http.close();

  Map<String, dynamic> _asObject(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException('The server sent an unexpected response.');
  }

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    bool nullOn404 = false,
  }) async {
    final token = tokenStore.token;
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to answer. Please try again.',
      );
    } on Exception {
      throw const ApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    final status = response.statusCode;
    final decoded = _decode(response);
    if (status >= 200 && status < 300) return decoded;
    if (status == 404 && nullOn404) return null;
    if (status == 401 && token != null) onUnauthorized?.call();
    throw ApiException(
      _errorMessage(status, decoded),
      statusCode: status,
      body: decoded,
    );
  }

  Object? _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  String _errorMessage(int status, Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is Map<String, dynamic>) {
        final text = detail['message'] ?? detail['detail'];
        if (text is String && text.isNotEmpty) return text;
      }
      if (detail is List) {
        // FastAPI validation errors: [{loc: [...], msg: "..."}]
        final parts = detail.map((e) {
          if (e is Map<String, dynamic>) {
            final loc = e['loc'];
            final field = loc is List && loc.isNotEmpty ? loc.last : null;
            final msg = e['msg']?.toString() ?? 'invalid value';
            return field == null || field == 'body' ? msg : '$field: $msg';
          }
          return e.toString();
        }).toList();
        if (parts.isNotEmpty) return parts.join('; ');
      }
    }
    return switch (status) {
      401 => 'You are not signed in.',
      403 => 'You do not have permission to do this.',
      404 => 'Not found.',
      _ => 'Something went wrong (error $status). Please try again.',
    };
  }
}

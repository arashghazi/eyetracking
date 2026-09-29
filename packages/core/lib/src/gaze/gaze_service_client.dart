import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/gaze.dart';

/// Where the gaze estimator is reached.
enum GazeMode {
  /// The gaze service on the PC, `GAZE_BASE_URL`, no authentication.
  local,

  /// The `/gaze/*` endpoints of the research server with the bearer token
  /// (secure path for phones).
  server,
}

/// Address of the local gaze service; override with
/// `--dart-define=GAZE_BASE_URL=...`.
const gazeBaseUrl = String.fromEnvironment(
  'GAZE_BASE_URL',
  defaultValue: 'http://localhost:8100',
);

const _gazeModeName = String.fromEnvironment('GAZE_MODE', defaultValue: 'local');

/// `--dart-define=GAZE_MODE=local|server`, default local.
GazeMode get configuredGazeMode =>
    _gazeModeName == 'server' ? GazeMode.server : GazeMode.local;

/// Port for the gaze estimator so controllers can be tested with fakes.
abstract class GazeEstimator {
  Future<GazeInfo> info();

  /// Sends one JPEG frame; the service processes it in memory and returns
  /// only numbers. [tMs] is the client's monotonic clock.
  Future<RawGazeSample> estimate(
    Uint8List jpegBytes,
    int tMs,
    int frameW,
    int frameH,
  );
}

/// HTTP client for the gaze service, local or through the research server.
class GazeServiceClient implements GazeEstimator {
  GazeServiceClient._(this._api, this._prefix, this.mode);

  /// Talks to the gaze service directly (no token).
  factory GazeServiceClient.local({
    String baseUrl = gazeBaseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 8),
  }) =>
      GazeServiceClient._(
        ApiClient(baseUrl: baseUrl, httpClient: httpClient, timeout: timeout),
        '',
        GazeMode.local,
      );

  /// Talks to `/gaze/*` on the research server, with [api]'s bearer token.
  factory GazeServiceClient.viaResearchServer(ApiClient api) =>
      GazeServiceClient._(api, '/gaze', GazeMode.server);

  /// Chooses the path from `--dart-define=GAZE_MODE`.
  factory GazeServiceClient.fromEnvironment(
    ApiClient researchApi, {
    GazeMode? mode,
  }) =>
      (mode ?? configuredGazeMode) == GazeMode.server
          ? GazeServiceClient.viaResearchServer(researchApi)
          : GazeServiceClient.local();

  final ApiClient _api;
  final String _prefix;
  final GazeMode mode;

  @override
  Future<GazeInfo> info() async {
    try {
      return GazeInfo.fromJson(await _api.getObject('$_prefix/info'));
    } on ApiException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<RawGazeSample> estimate(
    Uint8List jpegBytes,
    int tMs,
    int frameW,
    int frameH,
  ) async {
    try {
      final json = await _api.postObject('$_prefix/estimate', {
        'image_b64': base64Encode(jpegBytes),
        't_ms': tMs,
        'frame_w': frameW,
        'frame_h': frameH,
      });
      return RawGazeSample.fromJson(json, fallbackTMs: tMs);
    } on ApiException catch (e) {
      throw _friendly(e);
    }
  }

  ApiException _friendly(ApiException e) => e.isNetworkError
      ? ApiException(
          mode == GazeMode.local
              ? 'Could not reach the gaze service. Check that it is running.'
              : 'Could not reach the gaze service through the research server.',
        )
      : e;
}

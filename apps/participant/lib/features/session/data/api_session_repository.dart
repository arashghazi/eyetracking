import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/session_repository.dart';

class ApiSessionRepository implements SessionRepository {
  ApiSessionRepository(this._api);

  final ApiClient _api;

  String _base(String id) => '/me/sessions/${Uri.encodeComponent(id)}';

  @override
  Future<MeasurementSettings> measurementSettings() async =>
      MeasurementSettings.fromJson(
        await _api.getObject('/me/measurement-settings'),
      );

  @override
  Future<Readiness> readiness() async => Readiness.fromJson(
        (await _api.getObject('/me/participant'))['readiness']
                as Map<String, dynamic>? ??
            const {},
      );

  @override
  Future<SessionSummary> create(SessionCreateRequest request) async =>
      SessionSummary.fromJson(
        await _api.postObject('/me/sessions', request.toJson()),
      );

  @override
  Future<SessionSummary> cameraCheck(
    String sessionId,
    CameraCheckRequest body,
  ) async =>
      SessionSummary.fromJson(
        await _api.postObject('${_base(sessionId)}/camera-check', body.toJson()),
      );

  @override
  Future<CalibrationResult> calibrate(
    String sessionId,
    List<CalibrationTargetCapture> targets,
  ) async =>
      CalibrationResult.fromJson(
        await _api.postObject('${_base(sessionId)}/calibration', {
          'targets': [for (final t in targets) t.toJson()],
        }),
      );

  @override
  Future<ValidationResult> validate(
    String sessionId,
    StimulusLayout layout,
    List<ValidationTargetCapture> targets,
  ) async =>
      ValidationResult.fromJson(
        await _api.postObject('${_base(sessionId)}/validation', {
          'layout': layout.toJson(),
          'targets': [for (final t in targets) t.toJson()],
        }),
      );

  @override
  Future<void> postLayout(
    String sessionId,
    SessionSegmentName segment,
    StimulusLayout layout,
  ) async {
    await _api.postObject('${_base(sessionId)}/layout', {
      'segment': segment.wire,
      'layout': layout.toJson(),
    });
  }

  @override
  Future<SampleAck> postSamples(
    String sessionId,
    List<RawGazeSample> samples,
  ) async =>
      SampleAck.fromJson(
        await _api.postObject('${_base(sessionId)}/samples', {
          'samples': [for (final s in samples) s.toJson()],
        }),
      );

  @override
  Future<SessionSummary> postEvent(
    String sessionId,
    SessionEventType type, {
    required int tMs,
    Map<String, dynamic>? payload,
  }) async =>
      SessionSummary.fromJson(
        await _api.postObject('${_base(sessionId)}/events', {
          't_ms': tMs,
          'type': type.wire,
          'payload': ?payload,
        }),
      );

  @override
  Future<SessionSummary> summary(String sessionId) async =>
      SessionSummary.fromJson(await _api.getObject(_base(sessionId)));

  @override
  Future<List<SessionSummary>> mine() async => [
        for (final s in await _api.getList('/me/sessions'))
          SessionSummary.fromJson(s as Map<String, dynamic>),
      ];
}

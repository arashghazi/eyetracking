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
      _summary(await _api.postObject('/me/sessions', request.toJson()));

  /// A protocol's real face image may be a signed path on the service; it is
  /// shown from the app's own origin, so it gets the service address.
  SessionSummary _summary(Map<String, dynamic> json) {
    final protocol = json['protocol'];
    final definition = protocol is Map ? protocol['definition'] : null;
    final gradual = definition is Map ? definition['gradual'] : null;
    final url = gradual is Map ? gradual['real_face_media_url'] : null;
    if (url is! String || !url.startsWith('/')) {
      return SessionSummary.fromJson(json);
    }
    return SessionSummary.fromJson({
      ...json,
      'protocol': {
        ...(protocol as Map<String, dynamic>),
        'definition': {
          ...(definition as Map<String, dynamic>),
          'gradual': {
            ...(gradual as Map<String, dynamic>),
            'real_face_media_url': _api.resolveUrl(url),
          },
        },
      },
    });
  }

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
    StimulusLayout layout, {
    int? stageIndex,
  }) async {
    await _api.postObject('${_base(sessionId)}/layout', {
      'segment': segment.wire,
      'layout': layout.toJson(),
      'stage_index': ?stageIndex,
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
      _summary(await _api.getObject(_base(sessionId)));

  @override
  Future<TrialAck> postTrials(
    String sessionId,
    List<TrialRecord> trials,
  ) async =>
      TrialAck.fromJson(
        await _api.postObject('${_base(sessionId)}/trials', {
          'trials': [for (final t in trials) t.toJson()],
        }),
      );

  @override
  Future<StageDecision> stageResult(
    String sessionId,
    int stageIndex, {
    int? comfortValue,
  }) async =>
      StageDecision.fromJson(
        await _api.postObject('${_base(sessionId)}/stage-result', {
          'stage_index': stageIndex,
          'comfort_value': ?comfortValue,
        }),
      );

  @override
  Future<AnswerResult> postAnswer(
    String sessionId,
    AnswerRequest answer,
  ) async =>
      AnswerResult.fromJson(
        await _api.postObject('${_base(sessionId)}/answers', answer.toJson()),
      );

  @override
  Future<List<SessionSummary>> mine() async => [
        for (final s in await _api.getList('/me/sessions'))
          SessionSummary.fromJson(s as Map<String, dynamic>),
      ];
}

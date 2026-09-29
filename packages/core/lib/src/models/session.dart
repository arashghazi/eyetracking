import 'gaze.dart';
import 'layout.dart';

double? _d(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
List<String> _strings(Object? v) =>
    [for (final e in (v as List<dynamic>? ?? const [])) e.toString()];

/// Session lifecycle as the server reports it.
abstract final class SessionStatus {
  static const created = 'created';
  static const cameraOk = 'camera_ok';
  static const calibrated = 'calibrated';
  static const validated = 'validated';
  static const running = 'running';
  static const paused = 'paused';
  static const ended = 'ended';
}

/// Plain-language label for a session status.
String sessionStatusLabel(String status) => switch (status) {
      SessionStatus.created => 'Started',
      SessionStatus.cameraOk => 'Camera checked',
      SessionStatus.calibrated => 'Calibrated',
      SessionStatus.validated => 'Validated',
      SessionStatus.running => 'In progress',
      SessionStatus.paused => 'Paused',
      SessionStatus.ended => 'Ended',
      _ => status,
    };

/// Plain-language name for a gaze region class.
String regionLabel(String? region) => switch (region) {
      'eye' => 'Eyes',
      'mouth' => 'Mouth',
      'face_other' => 'Rest of the face',
      'outside' => 'Outside the face',
      'uncertain' => 'Not sure',
      null => '-',
      _ => region,
    };

/// Status plus, for a finished session, how it ended.
String sessionOutcomeLabel(String status, String? endReason) =>
    status == SessionStatus.ended && endReason == EndReason.endedEarly
        ? 'Ended early'
        : (status == SessionStatus.ended && endReason == EndReason.completed
            ? 'Completed'
            : sessionStatusLabel(status));

/// Stimulus segment names the server accepts.
enum SessionSegmentName {
  baseline,
  practice,
  post,
  free;

  String get wire => name;
}

/// Event types the server accepts on `POST /sessions/{id}/events`.
enum SessionEventType {
  segmentStart('segment_start'),
  segmentEnd('segment_end'),
  pause('pause'),
  resume('resume'),
  end('end'),
  cameraChanged('camera_changed'),
  orientationChanged('orientation_changed'),
  zoomChanged('zoom_changed'),
  faceLost('face_lost'),
  faceFound('face_found'),
  comfortAnswer('comfort_answer'),
  note('note');

  const SessionEventType(this.wire);
  final String wire;
}

/// Reasons for `end` events.
abstract final class EndReason {
  static const completed = 'completed';
  static const endedEarly = 'ended_early';
}

// ---------------------------------------------------------------- requests

class DeviceInfo {
  const DeviceInfo({required this.platform, this.userAgent, this.model});

  final String platform;
  final String? userAgent;
  final String? model;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        if (userAgent != null) 'user_agent': userAgent,
        if (model != null) 'model': model,
      };
}

class CameraInfo {
  const CameraInfo({this.label, required this.w, required this.h});

  final String? label;
  final int w;
  final int h;

  Map<String, dynamic> toJson() => {
        if (label != null && label!.isNotEmpty) 'label': label,
        'w': w,
        'h': h,
      };
}

class SessionCreateRequest {
  const SessionCreateRequest({
    required this.device,
    required this.screen,
    required this.camera,
    required this.gazeModel,
  });

  final DeviceInfo device;
  final ScreenInfo screen;
  final CameraInfo camera;
  final GazeInfo gazeModel;

  Map<String, dynamic> toJson() => {
        'device': device.toJson(),
        'screen': screen.toJson(),
        'camera': camera.toJson(),
        'gaze_model': gazeModel.toModelJson(),
      };
}

class CameraCheckRequest {
  const CameraCheckRequest({
    required this.faceDetected,
    required this.faceConf,
    required this.lightingOk,
    required this.frameW,
    required this.frameH,
  });

  final bool faceDetected;
  final double faceConf;
  final bool lightingOk;
  final int frameW;
  final int frameH;

  Map<String, dynamic> toJson() => {
        'face_detected': faceDetected,
        'face_conf': faceConf,
        'lighting_ok': lightingOk,
        'frame_w': frameW,
        'frame_h': frameH,
      };
}

/// Samples collected while the participant looked at one calibration dot.
class CalibrationTargetCapture {
  const CalibrationTargetCapture({
    required this.x,
    required this.y,
    required this.samples,
  });

  final double x;
  final double y;
  final List<RawGazeSample> samples;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'samples': [for (final s in samples) s.toJson()],
      };
}

/// Samples collected while the participant looked at one validation dot.
/// [region] is `eye`, `mouth` or `outside`.
class ValidationTargetCapture {
  const ValidationTargetCapture({
    required this.region,
    required this.x,
    required this.y,
    required this.samples,
  });

  final String region;
  final double x;
  final double y;
  final List<RawGazeSample> samples;

  Map<String, dynamic> toJson() => {
        'region': region,
        'x': x,
        'y': y,
        'samples': [for (final s in samples) s.toJson()],
      };
}

class SampleAck {
  const SampleAck({required this.stored, required this.invalid});

  final int stored;
  final int invalid;

  factory SampleAck.fromJson(Map<String, dynamic> json) =>
      SampleAck(stored: _i(json['stored']), invalid: _i(json['invalid']));
}

// ---------------------------------------------------------------- results

class CalibrationTargetResult {
  const CalibrationTargetResult({
    required this.x,
    required this.y,
    required this.nValid,
    this.errPx,
  });

  final double x;
  final double y;
  final int nValid;
  final double? errPx;

  factory CalibrationTargetResult.fromJson(Map<String, dynamic> json) =>
      CalibrationTargetResult(
        x: _d(json['x']) ?? 0,
        y: _d(json['y']) ?? 0,
        nValid: _i(json['n_valid']),
        errPx: _d(json['err_px']),
      );
}

class CalibrationResult {
  const CalibrationResult({
    this.calibrationId,
    required this.residualPxMedian,
    this.residualPxP90,
    this.perTarget = const [],
    required this.accepted,
    this.reasons = const [],
  });

  final String? calibrationId;
  final double residualPxMedian;
  final double? residualPxP90;
  final List<CalibrationTargetResult> perTarget;
  final bool accepted;
  final List<String> reasons;

  factory CalibrationResult.fromJson(Map<String, dynamic> json) =>
      CalibrationResult(
        calibrationId: json['calibration_id']?.toString(),
        residualPxMedian: _d(json['residual_px_median']) ?? 0,
        residualPxP90: _d(json['residual_px_p90']),
        perTarget: [
          for (final t in (json['per_target'] as List<dynamic>? ?? const []))
            CalibrationTargetResult.fromJson(t as Map<String, dynamic>),
        ],
        accepted: json['accepted'] == true,
        reasons: _strings(json['reasons']),
      );
}

class ValidationTargetResult {
  const ValidationTargetResult({
    required this.region,
    required this.x,
    required this.y,
    required this.n,
    this.majority,
    required this.correct,
    this.uncertainShare = 0,
  });

  final String region;
  final double x;
  final double y;
  final int n;
  final String? majority;
  final bool correct;
  final double uncertainShare;

  factory ValidationTargetResult.fromJson(Map<String, dynamic> json) =>
      ValidationTargetResult(
        region: json['region']?.toString() ?? '',
        x: _d(json['x']) ?? 0,
        y: _d(json['y']) ?? 0,
        n: _i(json['n']),
        majority: json['majority']?.toString(),
        correct: json['correct'] == true,
        uncertainShare: _d(json['uncertain_share']) ?? 0,
      );
}

class ValidationResult {
  const ValidationResult({
    this.validationId,
    required this.passed,
    this.correctRatio = 0,
    this.uncertainRatio = 0,
    this.sizeRatio = 0,
    this.reasons = const [],
    this.targets = const [],
  });

  final String? validationId;
  final bool passed;
  final double correctRatio;
  final double uncertainRatio;
  final double sizeRatio;
  final List<String> reasons;
  final List<ValidationTargetResult> targets;

  factory ValidationResult.fromJson(Map<String, dynamic> json) =>
      ValidationResult(
        validationId: json['validation_id']?.toString(),
        passed: json['passed'] == true,
        correctRatio: _d(json['correct_ratio']) ?? 0,
        uncertainRatio: _d(json['uncertain_ratio']) ?? 0,
        sizeRatio: _d(json['size_ratio']) ?? 0,
        reasons: _strings(json['reasons']),
        targets: [
          for (final t in (json['targets'] as List<dynamic>? ?? const []))
            ValidationTargetResult.fromJson(t as Map<String, dynamic>),
        ],
      );
}

// ---------------------------------------------------------------- summary

class CalibrationSummary {
  const CalibrationSummary({
    required this.residualPxMedian,
    this.residualPxP90,
    this.points = 0,
  });

  final double residualPxMedian;
  final double? residualPxP90;
  final int points;

  static CalibrationSummary? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return CalibrationSummary(
      residualPxMedian: _d(value['residual_px_median']) ?? 0,
      residualPxP90: _d(value['residual_px_p90']),
      points: _i(value['points']),
    );
  }
}

/// Validation outcome inside a session summary. [targets] is only filled in
/// the researcher's session detail.
class ValidationSummary {
  const ValidationSummary({
    required this.passed,
    this.correctRatio = 0,
    this.uncertainRatio = 0,
    this.sizeRatio = 0,
    this.reasons = const [],
    this.targets = const [],
  });

  final bool passed;
  final double correctRatio;
  final double uncertainRatio;
  final double sizeRatio;
  final List<String> reasons;
  final List<ValidationTargetResult> targets;

  static ValidationSummary? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return ValidationSummary(
      passed: value['passed'] == true,
      correctRatio: _d(value['correct_ratio']) ?? 0,
      uncertainRatio: _d(value['uncertain_ratio']) ?? 0,
      sizeRatio: _d(value['size_ratio']) ?? 0,
      reasons: _strings(value['reasons']),
      targets: [
        for (final t in (value['targets'] as List<dynamic>? ?? const []))
          ValidationTargetResult.fromJson(t as Map<String, dynamic>),
      ],
    );
  }
}

/// Milliseconds of session time by data quality. Missing data is not
/// "not looking".
class Coverage {
  const Coverage({
    this.totalMs = 0,
    this.classifiableMs = 0,
    this.uncertainMs = 0,
    this.missingMs = 0,
  });

  final int totalMs;
  final int classifiableMs;
  final int uncertainMs;
  final int missingMs;

  /// Share of the session that could be classified, or null when empty.
  double? get classifiableShare =>
      totalMs > 0 ? classifiableMs / totalMs : null;

  factory Coverage.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const Coverage();
    return Coverage(
      totalMs: _i(value['total_ms']),
      classifiableMs: _i(value['classifiable_ms']),
      uncertainMs: _i(value['uncertain_ms']),
      missingMs: _i(value['missing_ms']),
    );
  }
}

class RegionShares {
  const RegionShares({
    this.eye = 0,
    this.mouth = 0,
    this.faceOther = 0,
    this.outside = 0,
  });

  final double eye;
  final double mouth;
  final double faceOther;
  final double outside;

  static RegionShares? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return RegionShares(
      eye: _d(value['eye']) ?? 0,
      mouth: _d(value['mouth']) ?? 0,
      faceOther: _d(value['face_other']) ?? 0,
      outside: _d(value['outside']) ?? 0,
    );
  }
}

/// Eye-region attention is only reported after a passed regional validation
/// on a real (non-synthetic) estimator; otherwise [evaluable] is false and
/// [reason] says why.
class EyeRegionAttention {
  const EyeRegionAttention({
    this.evaluable = false,
    this.share,
    this.reason,
  });

  final bool evaluable;
  final double? share;
  final String? reason;

  factory EyeRegionAttention.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const EyeRegionAttention();
    return EyeRegionAttention(
      evaluable: value['evaluable'] == true,
      share: _d(value['share']),
      reason: value['reason']?.toString(),
    );
  }
}

class SessionSegmentInfo {
  const SessionSegmentInfo({
    required this.label,
    required this.startedMs,
    this.endedMs,
  });

  final String label;
  final int startedMs;
  final int? endedMs;

  factory SessionSegmentInfo.fromJson(Map<String, dynamic> json) =>
      SessionSegmentInfo(
        label: json['label']?.toString() ?? '',
        startedMs: _i(json['started_ms']),
        endedMs: (json['ended_ms'] as num?)?.toInt(),
      );
}

/// Participant-facing and researcher-facing session summary.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.status,
    this.createdAt,
    this.endedAt,
    this.endReason,
    this.synthetic = false,
    this.calibrationValid = false,
    this.calibration,
    this.validation,
    this.coverage = const Coverage(),
    this.regionShares,
    this.faceRegionShare,
    this.eyeRegionAttention = const EyeRegionAttention(),
    this.segments = const [],
    this.eventsCount = 0,
    this.notes = const [],
  });

  final String id;
  final String status;
  final String? createdAt;
  final String? endedAt;

  /// `completed` or `ended_early` once the session is over.
  final String? endReason;
  final bool synthetic;
  final bool calibrationValid;
  final CalibrationSummary? calibration;
  final ValidationSummary? validation;
  final Coverage coverage;
  final RegionShares? regionShares;

  /// `face_region_attention.share`: share of classifiable time on the face.
  final double? faceRegionShare;
  final EyeRegionAttention eyeRegionAttention;
  final List<SessionSegmentInfo> segments;
  final int eventsCount;
  final List<String> notes;

  bool get isEnded => status == SessionStatus.ended;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    final face = json['face_region_attention'];
    return SessionSummary(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? SessionStatus.created,
      createdAt: json['created_at']?.toString(),
      endedAt: json['ended_at']?.toString(),
      endReason: json['end_reason']?.toString(),
      synthetic: json['synthetic'] == true,
      calibrationValid: json['calibration_valid'] == true,
      calibration: CalibrationSummary.maybeFromJson(json['calibration']),
      validation: ValidationSummary.maybeFromJson(json['validation']),
      coverage: Coverage.fromJson(json['coverage']),
      regionShares: RegionShares.maybeFromJson(json['region_shares']),
      faceRegionShare: face is Map<String, dynamic> ? _d(face['share']) : null,
      eyeRegionAttention:
          EyeRegionAttention.fromJson(json['eye_region_attention']),
      segments: [
        for (final s in (json['segments'] as List<dynamic>? ?? const []))
          SessionSegmentInfo.fromJson(s as Map<String, dynamic>),
      ],
      eventsCount: _i(json['events_count']),
      notes: _strings(json['notes']),
    );
  }
}

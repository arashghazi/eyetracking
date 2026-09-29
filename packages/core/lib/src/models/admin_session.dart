import 'layout.dart';
import 'session.dart';

/// One row of the researcher's session table.
class SessionListItem {
  const SessionListItem({
    required this.id,
    required this.participantCode,
    required this.status,
    this.createdAt,
    this.endedAt,
    this.synthetic = false,
    this.devicePlatform,
    this.calibrationResidualPx,
    this.validationPassed,
    this.coverage = const Coverage(),
    this.eyeRegionAttention = const EyeRegionAttention(),
  });

  final String id;
  final String participantCode;
  final String status;
  final String? createdAt;
  final String? endedAt;
  final bool synthetic;
  final String? devicePlatform;
  final double? calibrationResidualPx;

  /// Null when no validation has been run.
  final bool? validationPassed;
  final Coverage coverage;
  final EyeRegionAttention eyeRegionAttention;

  factory SessionListItem.fromJson(Map<String, dynamic> json) =>
      SessionListItem(
        id: json['id']?.toString() ?? '',
        participantCode: json['participant_code']?.toString() ?? '',
        status: json['status']?.toString() ?? SessionStatus.created,
        createdAt: json['created_at']?.toString(),
        endedAt: json['ended_at']?.toString(),
        synthetic: json['synthetic'] == true,
        devicePlatform: json['device_platform']?.toString(),
        calibrationResidualPx:
            (json['calibration_residual_px'] as num?)?.toDouble(),
        validationPassed: json['validation_passed'] as bool?,
        coverage: Coverage.fromJson(json['coverage']),
        eyeRegionAttention:
            EyeRegionAttention.fromJson(json['eye_region_attention']),
      );
}

class SessionEventRecord {
  const SessionEventRecord({
    required this.tMs,
    required this.type,
    this.payload,
  });

  final int tMs;
  final String type;
  final Map<String, dynamic>? payload;

  factory SessionEventRecord.fromJson(Map<String, dynamic> json) =>
      SessionEventRecord(
        tMs: (json['t_ms'] as num?)?.toInt() ?? 0,
        type: json['type']?.toString() ?? '',
        payload: json['payload'] is Map<String, dynamic>
            ? json['payload'] as Map<String, dynamic>
            : null,
      );
}

/// Full session as a researcher or analyst sees it.
class SessionDetail {
  const SessionDetail({
    required this.summary,
    this.participantCode = '',
    this.device = const {},
    this.screen,
    this.camera = const {},
    this.gazeModel = const {},
    this.events = const [],
    this.validationTargets = const [],
  });

  final SessionSummary summary;
  final String participantCode;
  final Map<String, dynamic> device;
  final ScreenInfo? screen;
  final Map<String, dynamic> camera;
  final Map<String, dynamic> gazeModel;
  final List<SessionEventRecord> events;

  /// Result per validation dot. The server may send them inside `validation`
  /// or next to it as `validation_targets`; both are accepted.
  final List<ValidationTargetResult> validationTargets;

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? v) =>
        v is Map<String, dynamic> ? v : const {};
    final summary = SessionSummary.fromJson(json);
    final loose = json['validation_targets'];
    return SessionDetail(
      summary: summary,
      validationTargets: summary.validation?.targets.isNotEmpty == true
          ? summary.validation!.targets
          : [
              if (loose is List)
                for (final t in loose)
                  ValidationTargetResult.fromJson(t as Map<String, dynamic>),
            ],
      participantCode: json['participant_code']?.toString() ?? '',
      device: map(json['device']),
      screen: json['screen'] is Map<String, dynamic>
          ? ScreenInfo.fromJson(json['screen'] as Map<String, dynamic>)
          : null,
      camera: map(json['camera']),
      gazeModel: map(json['gaze_model']),
      events: [
        for (final e in (json['events'] as List<dynamic>? ?? const []))
          SessionEventRecord.fromJson(e as Map<String, dynamic>),
      ],
    );
  }
}

/// One stored, classified gaze sample.
class SampleRow {
  const SampleRow({
    required this.tMs,
    this.x,
    this.y,
    this.conf,
    this.valid = false,
    this.region,
    this.segment,
  });

  final int tMs;
  final double? x;
  final double? y;
  final double? conf;
  final bool valid;
  final String? region;
  final String? segment;

  factory SampleRow.fromJson(Map<String, dynamic> json) => SampleRow(
        tMs: (json['t_ms'] as num?)?.toInt() ?? 0,
        x: (json['x'] as num?)?.toDouble(),
        y: (json['y'] as num?)?.toDouble(),
        conf: (json['conf'] as num?)?.toDouble(),
        valid: json['valid'] == true,
        region: json['region']?.toString(),
        segment: json['segment']?.toString(),
      );
}

class SamplesPage {
  const SamplesPage({required this.total, required this.items});

  final int total;
  final List<SampleRow> items;

  factory SamplesPage.fromJson(Map<String, dynamic> json) => SamplesPage(
        total: (json['total'] as num?)?.toInt() ?? 0,
        items: [
          for (final e in (json['items'] as List<dynamic>? ?? const []))
            SampleRow.fromJson(e as Map<String, dynamic>),
        ],
      );
}

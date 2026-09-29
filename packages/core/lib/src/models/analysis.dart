/// Wire models for the analysis view, exports and access log (step 4).
library;

import 'quality.dart';

// The server sends some numbers as text (the parts of a group key), so a
// number may arrive as either.
double? _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int? _n(Object? v) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null);
String? _s(Object? v) => v?.toString();

/// One session as a row of the analysis table (coded; never an email).
class AnalysisRow {
  const AnalysisRow({
    required this.sessionId,
    required this.participantCode,
    this.createdAt,
    this.path,
    this.protocolName,
    this.protocolVersion,
    this.devicePlatform,
    this.screen,
    this.estimator,
    this.synthetic = false,
    this.quality,
    this.qualityReasons = const [],
    this.calibrationResidualPx,
    this.validationPassed,
    this.sizeRatio,
    this.totalMs,
    this.classifiableShare,
    this.uncertainShare,
    this.missingShare,
    this.faceShare,
    this.eyeShare,
    this.baselineEyeShare,
    this.postEyeShare,
    this.eyeShareDelta,
    this.comprehensionShare,
    this.numberTaskShare,
    this.stagesCompleted,
    this.comfortMin,
    this.comfortMean,
    this.comfortLowCount,
    this.pauses,
    this.endedEarly = false,
    this.improvement,
    this.groupKey = '',
    this.demographics = const {},
  });

  final String sessionId;
  final String participantCode;
  final String? createdAt;
  final String? path;
  final String? protocolName;
  final int? protocolVersion;
  final String? devicePlatform;
  final String? screen;
  final String? estimator;
  final bool synthetic;

  /// `ok`, `review` or `exclude`.
  final String? quality;
  final List<String> qualityReasons;
  final double? calibrationResidualPx;
  final bool? validationPassed;
  final double? sizeRatio;
  final int? totalMs;
  final double? classifiableShare;
  final double? uncertainShare;
  final double? missingShare;
  final double? faceShare;
  final double? eyeShare;
  final double? baselineEyeShare;
  final double? postEyeShare;

  /// Post minus baseline eye share (a fraction, so 0.12 is 12 points).
  final double? eyeShareDelta;
  final double? comprehensionShare;
  final double? numberTaskShare;
  final int? stagesCompleted;
  final int? comfortMin;
  final double? comfortMean;
  final int? comfortLowCount;
  final int? pauses;
  final bool endedEarly;
  final bool? improvement;
  final String groupKey;
  final Map<String, Object?> demographics;

  SessionQuality? get qualityInfo =>
      quality == null ? null : SessionQuality(grade: quality!, reasons: qualityReasons);

  factory AnalysisRow.fromJson(Map<String, dynamic> j) {
    final demo = j['demographics'];
    // A list, or the reasons joined with ";" as the export has them.
    final reasons = j['quality_reasons'];
    return AnalysisRow(
      sessionId: j['session_id']?.toString() ?? '',
      participantCode: j['participant_code']?.toString() ?? '',
      createdAt: _s(j['created_at']),
      path: _s(j['path']),
      protocolName: _s(j['protocol_name']),
      protocolVersion: _n(j['protocol_version']),
      devicePlatform: _s(j['device_platform']),
      screen: _s(j['screen']),
      estimator: _s(j['estimator']),
      synthetic: j['synthetic'] == true,
      quality: _s(j['quality']),
      qualityReasons: [
        if (reasons is List)
          for (final r in reasons) r.toString()
        else if (reasons is String)
          for (final r in reasons.split(';'))
            if (r.trim().isNotEmpty) r.trim(),
      ],
      calibrationResidualPx: _d(j['calibration_residual_px']),
      validationPassed: j['validation_passed'] as bool?,
      sizeRatio: _d(j['size_ratio']),
      totalMs: _n(j['total_ms']),
      classifiableShare: _d(j['classifiable_share']),
      uncertainShare: _d(j['uncertain_share']),
      missingShare: _d(j['missing_share']),
      faceShare: _d(j['face_share']),
      eyeShare: _d(j['eye_share']),
      baselineEyeShare: _d(j['baseline_eye_share']),
      postEyeShare: _d(j['post_eye_share']),
      eyeShareDelta: _d(j['eye_share_delta']),
      comprehensionShare: _d(j['comprehension_share']),
      numberTaskShare: _d(j['number_task_share']),
      stagesCompleted: _n(j['stages_completed']),
      comfortMin: _n(j['comfort_min']),
      comfortMean: _d(j['comfort_mean']),
      comfortLowCount: _n(j['comfort_low_count']),
      pauses: _n(j['pauses']),
      endedEarly: j['ended_early'] == true,
      improvement: j['improvement'] as bool?,
      groupKey: j['group_key']?.toString() ?? '',
      demographics: demo is Map<String, dynamic> ? demo : const {},
    );
  }
}

/// Sessions that may be compared with each other: same device platform,
/// protocol version, estimator model and stimulus size bucket.
class AnalysisGroup {
  const AnalysisGroup({
    required this.groupKey,
    this.devicePlatform,
    this.protocolVersion,
    this.estimator,
    this.screenBucket,
    this.stimulusBucket,
    this.sessions = 0,
    this.participants = 0,
  });

  final String groupKey;
  final String? devicePlatform;
  final int? protocolVersion;
  final String? estimator;
  final String? screenBucket;

  /// The stimulus size bucket as the server writes it, for example `150px`.
  final String? stimulusBucket;
  final int sessions;
  final int participants;

  factory AnalysisGroup.fromJson(Map<String, dynamic> j) => AnalysisGroup(
        groupKey: j['group_key']?.toString() ?? '',
        devicePlatform: _s(j['device_platform']),
        protocolVersion: _n(j['protocol_version']),
        estimator: _s(j['estimator']),
        screenBucket: _s(j['screen_bucket']),
        stimulusBucket: _s(j['stimulus_bucket_px']),
        sessions: _n(j['sessions']) ?? 0,
        participants: _n(j['participants']) ?? 0,
      );
}

/// One session of a participant's trend within one comparable group.
class TrendPoint {
  const TrendPoint({
    required this.sessionId,
    this.createdAt,
    this.baselineEyeShare,
    this.postEyeShare,
    this.comfortMean,
    this.comprehensionShare,
    this.numberTaskShare,
    this.quality,
  });

  final String sessionId;
  final String? createdAt;
  final double? baselineEyeShare;
  final double? postEyeShare;
  final double? comfortMean;
  final double? comprehensionShare;
  final double? numberTaskShare;
  final String? quality;

  /// Eye shares exist only after a passed validation on a real estimator;
  /// without them the session is "not evaluable" and is drawn hollow.
  bool get evaluable => baselineEyeShare != null && postEyeShare != null;

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        sessionId: j['session_id']?.toString() ?? '',
        createdAt: _s(j['created_at']),
        baselineEyeShare: _d(j['baseline_eye_share']),
        postEyeShare: _d(j['post_eye_share']),
        comfortMean: _d(j['comfort_mean']),
        comprehensionShare: _d(j['comprehension_share']),
        numberTaskShare: _d(j['number_task_share']),
        quality: _s(j['quality']),
      );
}

/// One participant's sessions inside one comparable group.
class AnalysisTrend {
  const AnalysisTrend({
    required this.participantCode,
    required this.groupKey,
    this.points = const [],
  });

  final String participantCode;
  final String groupKey;

  /// Sessions, oldest first.
  final List<TrendPoint> points;

  factory AnalysisTrend.fromJson(Map<String, dynamic> j) {
    final points = [
      if (j['points'] is List)
        for (final p in j['points'] as List)
          if (p is Map<String, dynamic>) TrendPoint.fromJson(p),
    ];
    // Ordered by date; ISO strings sort correctly, missing dates keep order.
    final indexed = [for (var i = 0; i < points.length; i++) (i, points[i])]
      ..sort((a, b) {
        final ad = a.$2.createdAt ?? '';
        final bd = b.$2.createdAt ?? '';
        final c = ad.compareTo(bd);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return AnalysisTrend(
      participantCode: j['participant_code']?.toString() ?? '',
      groupKey: j['group_key']?.toString() ?? '',
      points: [for (final e in indexed) e.$2],
    );
  }
}

/// `GET /studies/{id}/analysis`.
class AnalysisResponse {
  const AnalysisResponse({
    this.filters = const {},
    this.rows = const [],
    this.groups = const [],
    this.trends = const [],
    this.excluded = 0,
    this.note = '',
  });

  final Map<String, Object?> filters;
  final List<AnalysisRow> rows;
  final List<AnalysisGroup> groups;
  final List<AnalysisTrend> trends;

  /// Sessions left out by the quality and synthetic filters.
  final int excluded;

  /// Server note, e.g. that different groups are never pooled.
  final String note;

  factory AnalysisResponse.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(Object? v, T Function(Map<String, dynamic>) f) => [
          if (v is List)
            for (final e in v)
              if (e is Map<String, dynamic>) f(e),
        ];
    final filters = j['filters'];
    return AnalysisResponse(
      filters: filters is Map<String, dynamic> ? filters : const {},
      rows: list(j['rows'], AnalysisRow.fromJson),
      groups: list(j['groups'], AnalysisGroup.fromJson),
      trends: list(j['trends'], AnalysisTrend.fromJson),
      excluded: _n(j['excluded']) ?? 0,
      note: j['note']?.toString() ?? '',
    );
  }
}

/// One line of a study's access log.
class AccessLogEntry {
  const AccessLogEntry({
    required this.at,
    this.userId,
    this.role = '',
    required this.action,
    this.detail = '',
  });

  final String at;
  final String? userId;
  final String role;
  final String action;

  /// The detail as text (objects are shown as compact JSON).
  final String detail;

  factory AccessLogEntry.fromJson(Map<String, dynamic> j) {
    final detail = j['detail'];
    return AccessLogEntry(
      at: j['at']?.toString() ?? '',
      userId: _s(j['user_id']),
      role: j['role']?.toString() ?? '',
      action: j['action']?.toString() ?? '',
      detail: switch (detail) {
        null => '',
        String s => s,
        _ => _compactJson(detail),
      },
    );
  }
}

String _compactJson(Object value) {
  if (value is Map) {
    return value.entries.map((e) => '${e.key}: ${_compactJson(e.value as Object)}').join(', ');
  }
  if (value is List) return value.map((e) => _compactJson(e as Object)).join(', ');
  return '$value';
}

/// One field of the data dictionary: what an exported column means.
class DictionaryEntry {
  const DictionaryEntry({
    required this.name,
    this.type = '',
    this.unit = '',
    this.meaning = '',
  });

  final String name;
  final String type;
  final String unit;
  final String meaning;

  /// Reads the dictionary in any of the shapes a server may reasonably use:
  /// a list of entries, `{fields|columns|entries: [...]}`, or a map from
  /// name to `{type, unit, meaning}`.
  static List<DictionaryEntry> listFromJson(Object? value) {
    Object? body = value;
    if (body is Map<String, dynamic>) {
      for (final key in const ['fields', 'columns', 'entries', 'dictionary']) {
        if (body is Map<String, dynamic> && body[key] is List) {
          body = body[key];
          break;
        }
      }
    }
    if (body is List) {
      return [
        for (final e in body)
          if (e is Map<String, dynamic>) DictionaryEntry._fromMap(e, null),
      ];
    }
    if (body is Map<String, dynamic>) {
      return [
        for (final e in body.entries)
          if (e.value is Map<String, dynamic>)
            DictionaryEntry._fromMap(e.value as Map<String, dynamic>, e.key)
          else
            DictionaryEntry(name: e.key, meaning: '${e.value}'),
      ];
    }
    return const [];
  }

  factory DictionaryEntry._fromMap(Map<String, dynamic> j, String? name) =>
      DictionaryEntry(
        name: (j['name'] ?? j['field'] ?? j['column'] ?? name ?? '').toString(),
        type: j['type']?.toString() ?? '',
        unit: j['unit']?.toString() ?? '',
        meaning: (j['meaning'] ?? j['description'] ?? '').toString(),
      );
}

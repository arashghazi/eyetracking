/// Supervised pilot (build step 6): settings history, threshold review,
/// supervisor observations, the live monitor, the debrief form, the research
/// eye-tracker comparison and the pilot report.
///
/// Everything here is read from coded data: participants appear only as
/// research codes. Parsing is tolerant: a missing or null field becomes a
/// default or null, never an exception.
library;

import 'quality.dart';

double? _dbl(Object? v) => v is num ? v.toDouble() : null;
double _num(Object? v, [double fallback = 0]) => _dbl(v) ?? fallback;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
int _int(Object? v, [int fallback = 0]) => _intOrNull(v) ?? fallback;
bool? _boolOrNull(Object? v) => v is bool ? v : null;

String? _text(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

String _str(Object? v, [String fallback = '']) => v?.toString() ?? fallback;

Map<String, dynamic> _map(Object? v) => v is Map
    ? {for (final e in v.entries) e.key.toString(): e.value}
    : const <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) _map(e),
    ];

List<String> _strings(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e != null) e.toString(),
    ];

Map<String, int> _counts(Object? v) => {
      for (final e in _map(v).entries) e.key: _int(e.value),
    };

// ---------------------------------------------------------------- settings

/// The eight thresholds a study keeps, as the settings history and the
/// threshold review report them.
class SettingsValues {
  const SettingsValues({
    this.validationMinCorrect = 0.8,
    this.validationMaxUncertain = 0.2,
    this.minRegionToErrorRatio = 2.0,
    this.gazeConfThreshold = 0.5,
    this.calibrationPoints = 9,
    this.allowContinueWithoutValidation = true,
    this.qualityMaxUncertainShare = 0.2,
    this.qualityMaxMissingShare = 0.2,
  });

  /// Wire names, in the order the history and the review show them.
  static const keys = [
    'validation_min_correct',
    'validation_max_uncertain',
    'min_region_to_error_ratio',
    'gaze_conf_threshold',
    'calibration_points',
    'allow_continue_without_validation',
    'quality_max_uncertain_share',
    'quality_max_missing_share',
  ];

  final double validationMinCorrect;
  final double validationMaxUncertain;
  final double minRegionToErrorRatio;
  final double gazeConfThreshold;
  final int calibrationPoints;
  final bool allowContinueWithoutValidation;
  final double qualityMaxUncertainShare;
  final double qualityMaxMissingShare;

  factory SettingsValues.fromJson(Object? value) {
    final json = _map(value);
    const d = SettingsValues();
    return SettingsValues(
      validationMinCorrect:
          _num(json['validation_min_correct'], d.validationMinCorrect),
      validationMaxUncertain:
          _num(json['validation_max_uncertain'], d.validationMaxUncertain),
      minRegionToErrorRatio:
          _num(json['min_region_to_error_ratio'], d.minRegionToErrorRatio),
      gazeConfThreshold:
          _num(json['gaze_conf_threshold'], d.gazeConfThreshold),
      calibrationPoints: _int(json['calibration_points'], d.calibrationPoints),
      allowContinueWithoutValidation:
          _boolOrNull(json['allow_continue_without_validation']) ??
              d.allowContinueWithoutValidation,
      qualityMaxUncertainShare:
          _num(json['quality_max_uncertain_share'], d.qualityMaxUncertainShare),
      qualityMaxMissingShare:
          _num(json['quality_max_missing_share'], d.qualityMaxMissingShare),
    );
  }

  /// The value of one setting by its wire name.
  Object? operator [](String key) => switch (key) {
        'validation_min_correct' => validationMinCorrect,
        'validation_max_uncertain' => validationMaxUncertain,
        'min_region_to_error_ratio' => minRegionToErrorRatio,
        'gaze_conf_threshold' => gazeConfThreshold,
        'calibration_points' => calibrationPoints,
        'allow_continue_without_validation' => allowContinueWithoutValidation,
        'quality_max_uncertain_share' => qualityMaxUncertainShare,
        'quality_max_missing_share' => qualityMaxMissingShare,
        _ => null,
      };

  Map<String, dynamic> toJson() => {for (final k in keys) k: this[k]};

  /// What differs from [previous], in [keys] order. Without a previous
  /// version nothing is reported as changed.
  List<SettingChange> changesFrom(SettingsValues? previous) => [
        if (previous != null)
          for (final k in keys)
            if (this[k] != previous[k])
              SettingChange(key: k, before: previous[k], after: this[k]),
      ];
}

/// One setting that differs between two versions.
class SettingChange {
  const SettingChange({required this.key, this.before, this.after});

  final String key;
  final Object? before;
  final Object? after;

  String get label => settingLabel(key);

  /// `0.8 -> 0.7` with the values as people read them.
  String get text => '${formatSettingValue(before)} -> ${formatSettingValue(after)}';
}

/// Plain-language name of a setting.
String settingLabel(String key) => switch (key) {
      'validation_min_correct' => 'Minimum correct share',
      'validation_max_uncertain' => 'Maximum uncertain share',
      'min_region_to_error_ratio' => 'Minimum region-to-error ratio',
      'gaze_conf_threshold' => 'Gaze confidence threshold',
      'calibration_points' => 'Calibration points',
      'allow_continue_without_validation' =>
        'Allow continuing without validation',
      'quality_max_uncertain_share' => 'Quality: maximum uncertain share',
      'quality_max_missing_share' => 'Quality: maximum missing share',
      _ => key,
    };

/// A setting value without floating-point noise: `0.8`, `2`, `9`, `Yes`.
String formatSettingValue(Object? value) {
  if (value == null) return '-';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) {
    if (value == value.roundToDouble()) return value.round().toString();
    var text = value.toStringAsFixed(4);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
  return value.toString();
}

/// One entry of `GET /studies/{id}/measurement-settings/history`.
class SettingsVersion {
  const SettingsVersion({
    required this.version,
    this.values = const SettingsValues(),
    this.rationale = '',
    this.changedBy,
    this.createdAt,
  });

  final int version;
  final SettingsValues values;
  final String rationale;

  /// User id of the researcher who saved it; null for the synthesized first
  /// entry.
  final int? changedBy;

  /// Null for the synthesized entry that stands for the defaults.
  final String? createdAt;

  factory SettingsVersion.fromJson(Map<String, dynamic> json) => SettingsVersion(
        version: _int(json['version']),
        values: SettingsValues.fromJson(json['values']),
        rationale: _str(json['rationale']),
        changedBy: _intOrNull(json['changed_by']),
        createdAt: _text(json['created_at']),
      );

  static List<SettingsVersion> listFromJson(Object? value) => [
        for (final m in _maps(value)) SettingsVersion.fromJson(m),
      ];
}

/// `{version, values}` as the review and the report show the current settings.
class SettingsSnapshot {
  const SettingsSnapshot({this.version = 1, this.values = const SettingsValues()});

  final int version;
  final SettingsValues values;

  factory SettingsSnapshot.fromJson(Object? value) {
    final json = _map(value);
    return SettingsSnapshot(
      version: _int(json['version'], 1),
      values: SettingsValues.fromJson(json['values']),
    );
  }
}

// ------------------------------------------------------- small shared shapes

/// `{passed, reasons}` of a validation as re-judged or as stored.
class ValidationVerdict {
  const ValidationVerdict({this.passed = false, this.reasons = const []});

  final bool passed;
  final List<String> reasons;

  static ValidationVerdict? maybeFromJson(Object? value) {
    if (value is! Map) return null;
    final json = _map(value);
    return ValidationVerdict(
      passed: json['passed'] == true,
      reasons: _strings(json['reasons']),
    );
  }
}

/// `{n, min, p25, median, p75, p90, max}`; only `n` is present when there is
/// no data.
class MetricDistribution {
  const MetricDistribution({
    this.n = 0,
    this.min,
    this.p25,
    this.median,
    this.p75,
    this.p90,
    this.max,
  });

  final int n;
  final double? min;
  final double? p25;
  final double? median;
  final double? p75;
  final double? p90;
  final double? max;

  bool get isEmpty => n == 0;

  factory MetricDistribution.fromJson(Object? value) {
    final json = _map(value);
    return MetricDistribution(
      n: _int(json['n']),
      min: _dbl(json['min']),
      p25: _dbl(json['p25']),
      median: _dbl(json['median']),
      p75: _dbl(json['p75']),
      p90: _dbl(json['p90']),
      max: _dbl(json['max']),
    );
  }
}

/// How many sessions got each quality grade.
class QualityCounts {
  const QualityCounts({this.ok = 0, this.review = 0, this.exclude = 0});

  final int ok;
  final int review;
  final int exclude;

  int get total => ok + review + exclude;

  int count(String grade) => switch (grade) {
        QualityGrade.ok => ok,
        QualityGrade.review => review,
        QualityGrade.exclude => exclude,
        _ => 0,
      };

  factory QualityCounts.fromJson(Object? value) {
    final json = _map(value);
    return QualityCounts(
      ok: _int(json['ok']),
      review: _int(json['review']),
      exclude: _int(json['exclude']),
    );
  }
}

// -------------------------------------------------------- threshold review

/// The metrics a review row shows for one session.
class ReviewMetrics {
  const ReviewMetrics({
    this.correctRatio,
    this.uncertainRatio,
    this.sizeRatio,
    this.residualPxMedian,
  });

  final double? correctRatio;
  final double? uncertainRatio;
  final double? sizeRatio;
  final double? residualPxMedian;

  factory ReviewMetrics.fromJson(Object? value) {
    final json = _map(value);
    return ReviewMetrics(
      correctRatio: _dbl(json['correct_ratio']),
      uncertainRatio: _dbl(json['uncertain_ratio']),
      sizeRatio: _dbl(json['size_ratio']),
      residualPxMedian: _dbl(json['residual_px_median']),
    );
  }
}

/// One session in a threshold review, judged under the current and the
/// candidate thresholds.
class ThresholdReviewRow {
  const ThresholdReviewRow({
    required this.sessionId,
    this.participantCode = '',
    this.createdAt,
    this.devicePlatform,
    this.synthetic = false,
    this.settingsVersion,
    this.validationCurrent,
    this.validationCandidate,
    this.qualityCurrent,
    this.qualityCandidate,
    this.changed = false,
    this.metrics = const ReviewMetrics(),
  });

  final String sessionId;
  final String participantCode;
  final String? createdAt;
  final String? devicePlatform;
  final bool synthetic;

  /// Settings version the session's validation was judged with.
  final int? settingsVersion;

  /// Null when the session has no validation.
  final ValidationVerdict? validationCurrent;
  final ValidationVerdict? validationCandidate;
  final SessionQuality? qualityCurrent;
  final SessionQuality? qualityCandidate;
  final bool changed;
  final ReviewMetrics metrics;

  factory ThresholdReviewRow.fromJson(Map<String, dynamic> json) =>
      ThresholdReviewRow(
        sessionId: _str(json['session_id']),
        participantCode: _str(json['participant_code']),
        createdAt: _text(json['created_at']),
        devicePlatform: _text(json['device_platform']),
        synthetic: json['synthetic'] == true,
        settingsVersion: _intOrNull(json['settings_version']),
        validationCurrent: ValidationVerdict.maybeFromJson(json['validation_current']),
        validationCandidate:
            ValidationVerdict.maybeFromJson(json['validation_candidate']),
        qualityCurrent: SessionQuality.maybeFromJson(json['quality_current']),
        qualityCandidate: SessionQuality.maybeFromJson(json['quality_candidate']),
        changed: json['changed'] == true,
        metrics: ReviewMetrics.fromJson(json['metrics']),
      );
}

/// Validation pass counts under the current and the candidate thresholds.
class PassCounts {
  const PassCounts({this.current = 0, this.candidate = 0});

  final int current;
  final int candidate;

  factory PassCounts.fromJson(Object? value) {
    final json = _map(value);
    return PassCounts(
      current: _int(json['current']),
      candidate: _int(json['candidate']),
    );
  }
}

/// One device platform in a threshold review.
class ReviewDeviceRow {
  const ReviewDeviceRow({
    this.devicePlatform = 'unknown',
    this.sessions = 0,
    this.validated = 0,
    this.passCurrent = 0,
    this.passCandidate = 0,
  });

  final String devicePlatform;
  final int sessions;
  final int validated;
  final int passCurrent;
  final int passCandidate;

  factory ReviewDeviceRow.fromJson(Map<String, dynamic> json) => ReviewDeviceRow(
        devicePlatform: _str(json['device_platform'], 'unknown'),
        sessions: _int(json['sessions']),
        validated: _int(json['validated']),
        passCurrent: _int(json['pass_current']),
        passCandidate: _int(json['pass_candidate']),
      );
}

/// `POST /studies/{id}/pilot/threshold-review`: what candidate thresholds
/// would change on the recorded sessions. Nothing is saved.
class ThresholdReview {
  const ThresholdReview({
    this.current = const SettingsSnapshot(),
    this.candidateValues = const SettingsValues(),
    this.changes = const {},
    this.sessions = 0,
    this.skippedSynthetic = 0,
    this.includesSynthetic = false,
    this.validatedSessions = 0,
    this.validationPass = const PassCounts(),
    this.qualityCurrent = const QualityCounts(),
    this.qualityCandidate = const QualityCounts(),
    this.changedSessions = 0,
    this.distributions = const {},
    this.byDevice = const [],
    this.rows = const [],
    this.notes = const [],
  });

  /// The metrics the server reports distributions for, in display order.
  static const distributionKeys = [
    'correct_ratio',
    'uncertain_ratio',
    'size_ratio',
    'residual_px_median',
    'uncertain_share',
    'missing_share',
  ];

  final SettingsSnapshot current;
  final SettingsValues candidateValues;

  /// The fields the candidate changes, by wire name.
  final Map<String, dynamic> changes;
  final int sessions;
  final int skippedSynthetic;
  final bool includesSynthetic;
  final int validatedSessions;
  final PassCounts validationPass;
  final QualityCounts qualityCurrent;
  final QualityCounts qualityCandidate;
  final int changedSessions;
  final Map<String, MetricDistribution> distributions;
  final List<ReviewDeviceRow> byDevice;
  final List<ThresholdReviewRow> rows;
  final List<String> notes;

  factory ThresholdReview.fromJson(Map<String, dynamic> json) {
    final candidate = _map(json['candidate']);
    final quality = _map(json['quality']);
    return ThresholdReview(
      current: SettingsSnapshot.fromJson(json['current']),
      candidateValues: SettingsValues.fromJson(candidate['values']),
      changes: _map(candidate['changes']),
      sessions: _int(json['sessions']),
      skippedSynthetic: _int(json['skipped_synthetic']),
      includesSynthetic: json['includes_synthetic'] == true,
      validatedSessions: _int(json['validated_sessions']),
      validationPass: PassCounts.fromJson(json['validation_pass']),
      qualityCurrent: QualityCounts.fromJson(quality['current']),
      qualityCandidate: QualityCounts.fromJson(quality['candidate']),
      changedSessions: _int(json['changed_sessions']),
      distributions: {
        for (final e in _map(json['distributions']).entries)
          e.key: MetricDistribution.fromJson(e.value),
      },
      byDevice: [
        for (final m in _maps(json['by_device'])) ReviewDeviceRow.fromJson(m),
      ],
      rows: [
        for (final m in _maps(json['rows'])) ThresholdReviewRow.fromJson(m),
      ],
      notes: _strings(json['notes']),
    );
  }
}

// ------------------------------------------------------------ observations

abstract final class ObservationCategory {
  static const comfort = 'comfort';
  static const comprehension = 'comprehension';
  static const technical = 'technical';
  static const ux = 'ux';
  static const protocol = 'protocol';
  static const other = 'other';

  static const all = [comfort, comprehension, technical, ux, protocol, other];
}

abstract final class ObservationSeverity {
  static const info = 'info';
  static const minor = 'minor';
  static const major = 'major';
  static const stop = 'stop';

  static const all = [info, minor, major, stop];
}

/// The longest observation text the server accepts.
const int kMaxObservationChars = 2000;

String observationCategoryLabel(String category) => switch (category) {
      ObservationCategory.comfort => 'Comfort',
      ObservationCategory.comprehension => 'Comprehension',
      ObservationCategory.technical => 'Technical',
      ObservationCategory.ux => 'Usability',
      ObservationCategory.protocol => 'Protocol',
      ObservationCategory.other => 'Other',
      _ => category,
    };

String observationSeverityLabel(String severity) => switch (severity) {
      ObservationSeverity.info => 'Info',
      ObservationSeverity.minor => 'Minor',
      ObservationSeverity.major => 'Major',
      ObservationSeverity.stop => 'Stop',
      _ => severity,
    };

/// A supervisor's note under a session's research code. Observations cannot
/// be edited or deleted; a correction is a new observation.
class Observation {
  const Observation({
    required this.id,
    this.sessionId = '',
    this.authorId,
    this.category = ObservationCategory.other,
    this.severity = ObservationSeverity.info,
    this.text = '',
    this.tMs,
    this.createdAt,
    this.participantCode,
  });

  final String id;
  final String sessionId;
  final int? authorId;
  final String category;
  final String severity;
  final String text;

  /// Session time the note refers to; null when it is about the session as
  /// a whole.
  final int? tMs;
  final String? createdAt;

  /// Only in the pilot report, where observations of all sessions are listed.
  final String? participantCode;

  bool get isMajorOrStop =>
      severity == ObservationSeverity.major || severity == ObservationSeverity.stop;

  factory Observation.fromJson(Map<String, dynamic> json) => Observation(
        id: _str(json['id']),
        sessionId: _str(json['session_id']),
        authorId: _intOrNull(json['author_id']),
        category: _str(json['category'], ObservationCategory.other),
        severity: _str(json['severity'], ObservationSeverity.info),
        text: _str(json['text']),
        tMs: _intOrNull(json['t_ms']),
        createdAt: _text(json['created_at']),
        participantCode: _text(json['participant_code']),
      );

  static List<Observation> listFromJson(Object? value) => [
        for (final m in _maps(value)) Observation.fromJson(m),
      ];
}

/// `POST .../observations` body.
class ObservationRequest {
  const ObservationRequest({
    required this.category,
    this.severity = ObservationSeverity.info,
    required this.text,
    this.tMs,
  });

  final String category;
  final String severity;
  final String text;
  final int? tMs;

  Map<String, dynamic> toJson() => {
        'category': category,
        'severity': severity,
        'text': text,
        if (tMs != null) 't_ms': tMs,
      };
}

// -------------------------------------------------------------- live monitor

/// The last event of an active session.
class ActiveLastEvent {
  const ActiveLastEvent({this.type = '', this.tMs = 0, this.createdAt});

  final String type;
  final int tMs;
  final String? createdAt;

  static ActiveLastEvent? maybeFromJson(Object? value) {
    if (value is! Map) return null;
    final json = _map(value);
    return ActiveLastEvent(
      type: _str(json['type']),
      tMs: _int(json['t_ms']),
      createdAt: _text(json['created_at']),
    );
  }
}

/// One row of `GET /studies/{id}/pilot/active`.
class ActiveSession {
  const ActiveSession({
    required this.sessionId,
    this.participantCode = '',
    this.status = '',
    this.createdAt,
    this.devicePlatform,
    this.protocolId,
    this.lastEvent,
  });

  final String sessionId;
  final String participantCode;
  final String status;
  final String? createdAt;
  final String? devicePlatform;
  final String? protocolId;
  final ActiveLastEvent? lastEvent;

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
        sessionId: _str(json['session_id']),
        participantCode: _str(json['participant_code']),
        status: _str(json['status']),
        createdAt: _text(json['created_at']),
        devicePlatform: _text(json['device_platform']),
        protocolId: _text(json['protocol_id']),
        lastEvent: ActiveLastEvent.maybeFromJson(json['last_event']),
      );

  static List<ActiveSession> listFromJson(Object? value) => [
        for (final m in _maps(value)) ActiveSession.fromJson(m),
      ];
}

/// The gradual-stage decision of the last finished stage.
class LiveStageResult {
  const LiveStageResult({
    this.stageIndex = 0,
    this.decision = '',
    this.reason,
    this.comfortValue,
    this.correctRatio,
  });

  final int stageIndex;
  final String decision;
  final String? reason;
  final int? comfortValue;
  final double? correctRatio;

  static LiveStageResult? maybeFromJson(Object? value) {
    if (value is! Map) return null;
    final json = _map(value);
    return LiveStageResult(
      stageIndex: _int(json['stage_index']),
      decision: _str(json['decision']),
      reason: _text(json['reason']),
      comfortValue: _intOrNull(json['comfort_value']),
      correctRatio: _dbl(json['correct_ratio']),
    );
  }
}

/// The last few seconds of webcam samples.
class LiveRecent {
  const LiveRecent({this.samples = 0, this.validShare, this.regions = const {}});

  /// Regions in the order the monitor shows them.
  static const regionKeys = ['eye', 'mouth', 'face_other', 'outside', 'uncertain'];

  final int samples;

  /// Null when no sample fell into the window.
  final double? validShare;
  final Map<String, int> regions;

  int region(String key) => regions[key] ?? 0;

  factory LiveRecent.fromJson(Object? value) {
    final json = _map(value);
    return LiveRecent(
      samples: _int(json['samples']),
      validShare: _dbl(json['valid_share']),
      regions: _counts(json['regions']),
    );
  }
}

/// One of the last events of a live session.
class LiveEvent {
  const LiveEvent({this.tMs = 0, this.type = '', this.payload = const {}});

  final int tMs;
  final String type;
  final Map<String, dynamic> payload;

  factory LiveEvent.fromJson(Map<String, dynamic> json) => LiveEvent(
        tMs: _int(json['t_ms']),
        type: _str(json['type']),
        payload: _map(json['payload']),
      );
}

/// `GET /studies/{id}/sessions/{sid}/live`.
class LiveStatus {
  const LiveStatus({
    required this.sessionId,
    this.participantCode = '',
    this.status = '',
    this.synthetic = false,
    this.estimator,
    this.calibrationValid = false,
    this.validation,
    this.currentSegment,
    this.paused = false,
    this.pauses = 0,
    this.stageIndex,
    this.lastStageResult,
    this.samplesTotal = 0,
    this.lastSampleTMs,
    this.recentWindowMs = 10000,
    this.recent = const LiveRecent(),
    this.recentEvents = const [],
    this.secondsSinceLastEvent,
    this.observations = 0,
    this.endReason,
    this.note = '',
  });

  final String sessionId;
  final String participantCode;
  final String status;

  /// Recorded with a synthetic estimator: the region counts mean nothing.
  final bool synthetic;
  final String? estimator;
  final bool calibrationValid;
  final ValidationVerdict? validation;
  final String? currentSegment;
  final bool paused;
  final int pauses;
  final int? stageIndex;
  final LiveStageResult? lastStageResult;
  final int samplesTotal;

  /// Session time of the newest sample; what "use current session time" sends.
  final int? lastSampleTMs;
  final int recentWindowMs;
  final LiveRecent recent;

  /// The last events, oldest first.
  final List<LiveEvent> recentEvents;
  final double? secondsSinceLastEvent;

  /// How many observations the session has.
  final int observations;
  final String? endReason;
  final String note;

  bool get isEnded => status == 'ended';

  factory LiveStatus.fromJson(Map<String, dynamic> json) => LiveStatus(
        sessionId: _str(json['session_id']),
        participantCode: _str(json['participant_code']),
        status: _str(json['status']),
        synthetic: json['synthetic'] == true,
        estimator: _text(json['estimator']),
        calibrationValid: json['calibration_valid'] == true,
        validation: ValidationVerdict.maybeFromJson(json['validation']),
        currentSegment: _text(json['current_segment']),
        paused: json['paused'] == true,
        pauses: _int(json['pauses']),
        stageIndex: _intOrNull(json['stage_index']),
        lastStageResult: LiveStageResult.maybeFromJson(json['last_stage_result']),
        samplesTotal: _int(json['samples_total']),
        lastSampleTMs: _intOrNull(json['last_sample_t_ms']),
        recentWindowMs: _int(json['recent_window_ms'], 10000),
        recent: LiveRecent.fromJson(json['recent']),
        recentEvents: [
          for (final m in _maps(json['recent_events'])) LiveEvent.fromJson(m),
        ],
        secondsSinceLastEvent: _dbl(json['seconds_since_last_event']),
        observations: _int(json['observations']),
        endReason: _text(json['end_reason']),
        note: _str(json['note']),
      );
}

// ------------------------------------------------------------------ debrief

abstract final class DebriefQuestionType {
  static const scale = 'scale';
  static const yesNo = 'yes_no';
  static const choice = 'choice';
  static const text = 'text';

  static const all = [scale, yesNo, choice, text];
}

String debriefQuestionTypeLabel(String type) => switch (type) {
      DebriefQuestionType.scale => 'Scale',
      DebriefQuestionType.yesNo => 'Yes / no',
      DebriefQuestionType.choice => 'Choice',
      DebriefQuestionType.text => 'Free text',
      _ => type,
    };

/// One question of the short form a participant may answer after a session.
class DebriefQuestion {
  const DebriefQuestion({
    required this.key,
    this.type = DebriefQuestionType.text,
    this.prompt = '',
    this.required = false,
    this.scaleMax,
    this.labels = const [],
    this.options = const [],
  });

  /// `a-z`, `0-9` and `_`, starting with a letter, at most 40 characters.
  static final RegExp keyPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
  static const maxPromptChars = 300;
  static const minScaleMax = 2;
  static const maxScaleMax = 10;
  static const minOptions = 2;
  static const maxOptions = 10;
  static const maxQuestions = 20;

  final String key;
  final String type;
  final String prompt;
  final bool required;

  /// Scale questions only: the highest point (2 to 10).
  final int? scaleMax;

  /// Scale questions only: one label per point, or none.
  final List<String> labels;

  /// Choice questions only: 2 to 10 texts.
  final List<String> options;

  factory DebriefQuestion.fromJson(Map<String, dynamic> json) {
    final type = _str(json['type'], DebriefQuestionType.text);
    return DebriefQuestion(
      key: _str(json['key']),
      type: type,
      prompt: _str(json['prompt']),
      required: json['required'] == true,
      scaleMax: type == DebriefQuestionType.scale
          ? _int(json['scale_max'], 5)
          : _intOrNull(json['scale_max']),
      labels: _strings(json['labels']),
      options: _strings(json['options']),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        'prompt': prompt,
        'required': required,
        if (type == DebriefQuestionType.scale) ...{
          'scale_max': scaleMax ?? 5,
          'labels': labels,
        },
        if (type == DebriefQuestionType.choice) 'options': options,
      };

  static List<DebriefQuestion> listFromJson(Object? value) => [
        for (final m in _maps(value)) DebriefQuestion.fromJson(m),
      ];
}

/// `GET /studies/{id}/debrief-form`.
class DebriefForm {
  const DebriefForm({
    this.version = 0,
    this.enabled = false,
    this.questions = const [],
    this.saved = false,
  });

  /// 0 until the first save; then the questions are the suggested defaults.
  final int version;
  final bool enabled;
  final List<DebriefQuestion> questions;
  final bool saved;

  factory DebriefForm.fromJson(Map<String, dynamic> json) => DebriefForm(
        version: _int(json['version']),
        enabled: json['enabled'] == true,
        questions: DebriefQuestion.listFromJson(json['questions']),
        saved: json['saved'] == true,
      );
}

// ------------------------------------------------- research eye tracker

/// One imported export of a research eye tracker for a session.
class ReferenceRecording {
  const ReferenceRecording({
    required this.id,
    this.sessionId = '',
    this.source = '',
    this.settings = const {},
    this.sampleCount = 0,
    this.validCount = 0,
    this.uploadedBy,
    this.createdAt,
  });

  final String id;
  final String sessionId;
  final String source;

  /// The import settings, with `alignment` (`given_offset` or
  /// `estimated_from_data`) and, for the latter, `estimated_shift_ms`.
  final Map<String, dynamic> settings;
  final int sampleCount;
  final int validCount;
  final int? uploadedBy;
  final String? createdAt;

  String? get alignment => _text(settings['alignment']);
  bool get alignmentEstimated => alignment == 'estimated_from_data';
  double? get estimatedShiftMs => _dbl(settings['estimated_shift_ms']);

  factory ReferenceRecording.fromJson(Map<String, dynamic> json) =>
      ReferenceRecording(
        id: _str(json['id']),
        sessionId: _str(json['session_id']),
        source: _str(json['source']),
        settings: _map(json['settings']),
        sampleCount: _int(json['sample_count']),
        validCount: _int(json['valid_count']),
        uploadedBy: _intOrNull(json['uploaded_by']),
        createdAt: _text(json['created_at']),
      );

  static ReferenceRecording? maybeFromJson(Object? value) =>
      value is Map ? ReferenceRecording.fromJson(_map(value)) : null;

  static List<ReferenceRecording> listFromJson(Object? value) => [
        for (final m in _maps(value)) ReferenceRecording.fromJson(m),
      ];
}

abstract final class ReferenceTimeUnit {
  static const ms = 'ms';
  static const us = 'us';
  static const s = 's';

  static const all = [ms, us, s];
}

abstract final class ReferenceCoordSpace {
  static const cssPx = 'css_px';
  static const devicePx = 'device_px';
  static const norm = 'norm';

  static const all = [cssPx, devicePx, norm];
}

/// The multipart fields of `POST .../reference` next to the file.
class ReferenceImportRequest {
  const ReferenceImportRequest({
    required this.source,
    required this.timeColumn,
    required this.xColumn,
    required this.yColumn,
    this.validColumn = '',
    this.validValues = '',
    this.timeUnit = ReferenceTimeUnit.ms,
    this.offset = 0,
    this.coordSpace = ReferenceCoordSpace.cssPx,
    this.originX = 0,
    this.originY = 0,
    this.delimiter = '',
    this.autoAlignWindowMs = 0,
  });

  static const maxSourceChars = 120;
  static const maxAutoAlignWindowMs = 10000;

  final String source;
  final String timeColumn;
  final String xColumn;
  final String yColumn;
  final String validColumn;
  final String validValues;
  final String timeUnit;

  /// Tracker time at session `t_ms = 0`, in [timeUnit].
  final double offset;
  final String coordSpace;
  final double originX;
  final double originY;

  /// `,` `;` or a tab; empty lets the server guess.
  final String delimiter;

  /// 0 keeps the given offset; otherwise the server searches a shift within
  /// this window.
  final int autoAlignWindowMs;

  /// Text form fields as the server reads them; optional ones are left out
  /// when empty.
  Map<String, String> toFields() {
    String number(double v) =>
        v == v.roundToDouble() ? v.round().toString() : v.toString();
    return {
      'source': source.trim(),
      'time_column': timeColumn.trim(),
      'x_column': xColumn.trim(),
      'y_column': yColumn.trim(),
      if (validColumn.trim().isNotEmpty) 'valid_column': validColumn.trim(),
      if (validValues.trim().isNotEmpty) 'valid_values': validValues.trim(),
      'time_unit': timeUnit,
      'offset': number(offset),
      'coord_space': coordSpace,
      'origin_x': number(originX),
      'origin_y': number(originY),
      if (delimiter.isNotEmpty) 'delimiter': delimiter,
      'auto_align_window_ms': '$autoAlignWindowMs',
    };
  }
}

/// The 4 x 4 confusion matrix of the comparison: rows are what the webcam
/// said, columns what the research tracker said.
class ConfusionMatrix {
  const ConfusionMatrix([this.cells = const {}]);

  static const labels = ['eye', 'mouth', 'face_other', 'outside'];

  final Map<String, Map<String, int>> cells;

  int cell(String webcam, String reference) => cells[webcam]?[reference] ?? 0;
  int rowTotal(String webcam) =>
      labels.fold(0, (sum, ref) => sum + cell(webcam, ref));
  int columnTotal(String reference) =>
      labels.fold(0, (sum, web) => sum + cell(web, reference));
  int get total => labels.fold(0, (sum, web) => sum + rowTotal(web));

  factory ConfusionMatrix.fromJson(Object? value) {
    final rows = _map(_map(value)['rows_webcam_columns_reference']);
    return ConfusionMatrix({
      for (final e in rows.entries) e.key: _counts(e.value),
    });
  }
}

/// One stimulus segment of a comparison.
class ComparisonSegment {
  const ComparisonSegment({
    required this.segment,
    this.pairs = 0,
    this.webcamEyeShare,
    this.referenceEyeShare,
  });

  final String segment;
  final int pairs;
  final double? webcamEyeShare;
  final double? referenceEyeShare;

  factory ComparisonSegment.fromJson(Map<String, dynamic> json) =>
      ComparisonSegment(
        segment: _str(json['segment']),
        pairs: _int(json['pairs']),
        webcamEyeShare: _dbl(json['webcam_eye_share']),
        referenceEyeShare: _dbl(json['reference_eye_share']),
      );
}

/// The session a comparison was made for.
class ComparisonSession {
  const ComparisonSession({
    this.id = '',
    this.participantCode = '',
    this.estimator,
    this.gazeModelVersion,
    this.synthetic = false,
    this.validationPassed = false,
    this.screen = const {},
  });

  final String id;
  final String participantCode;
  final String? estimator;
  final String? gazeModelVersion;
  final bool synthetic;
  final bool validationPassed;
  final Map<String, dynamic> screen;

  factory ComparisonSession.fromJson(Object? value) {
    final json = _map(value);
    return ComparisonSession(
      id: _str(json['id']),
      participantCode: _str(json['participant_code']),
      estimator: _text(json['estimator']),
      gazeModelVersion: _text(json['gaze_model_version']),
      synthetic: json['synthetic'] == true,
      validationPassed: json['validation_passed'] == true,
      screen: _map(json['screen']),
    );
  }
}

/// `GET .../reference/{rid}/compare`: agreement between the webcam estimate
/// and a research tracker for one session on one computer. Not a general
/// accuracy claim.
class ReferenceComparison {
  const ReferenceComparison({
    this.toleranceMs = 40,
    this.webcamSamples = 0,
    this.pairedClassified = 0,
    this.webcamUncertainWhileReferenceValid = 0,
    this.referenceInvalid = 0,
    this.noReferenceInTime = 0,
    this.distancePx = const MetricDistribution(),
    this.biasX,
    this.biasY,
    this.regionAgreement,
    this.cohenKappa,
    this.confusion = const ConfusionMatrix(),
    this.eyePrecision,
    this.eyeRecall,
    this.segments = const [],
    this.note = '',
    this.recording,
    this.session = const ComparisonSession(),
    this.caveats = const [],
  });

  final int toleranceMs;
  final int webcamSamples;
  final int pairedClassified;
  final int webcamUncertainWhileReferenceValid;
  final int referenceInvalid;
  final int noReferenceInTime;

  /// Distance between the webcam point and the tracker point in CSS pixels.
  final MetricDistribution distancePx;
  final double? biasX;
  final double? biasY;
  final double? regionAgreement;
  final double? cohenKappa;
  final ConfusionMatrix confusion;
  final double? eyePrecision;
  final double? eyeRecall;
  final List<ComparisonSegment> segments;
  final String note;
  final ReferenceRecording? recording;
  final ComparisonSession session;

  /// What weakens the numbers: a synthetic estimator, an alignment estimated
  /// from the same data, a failed validation.
  final List<String> caveats;

  factory ReferenceComparison.fromJson(Map<String, dynamic> json) {
    final bias = _map(json['bias_px']);
    final eye = _map(json['eye_region']);
    return ReferenceComparison(
      toleranceMs: _int(json['tolerance_ms'], 40),
      webcamSamples: _int(json['webcam_samples']),
      pairedClassified: _int(json['paired_classified']),
      webcamUncertainWhileReferenceValid:
          _int(json['webcam_uncertain_while_reference_valid']),
      referenceInvalid: _int(json['reference_invalid']),
      noReferenceInTime: _int(json['no_reference_in_time']),
      distancePx: MetricDistribution.fromJson(json['distance_px']),
      biasX: _dbl(bias['x']),
      biasY: _dbl(bias['y']),
      regionAgreement: _dbl(json['region_agreement']),
      cohenKappa: _dbl(json['cohen_kappa']),
      confusion: ConfusionMatrix.fromJson(json['confusion']),
      eyePrecision: _dbl(eye['precision']),
      eyeRecall: _dbl(eye['recall']),
      segments: [
        for (final m in _maps(json['segments'])) ComparisonSegment.fromJson(m),
      ],
      note: _str(json['note']),
      recording: ReferenceRecording.maybeFromJson(json['recording']),
      session: ComparisonSession.fromJson(json['session']),
      caveats: _strings(json['caveats']),
    );
  }
}

// ------------------------------------------------------------ pilot report

/// One session row of the pilot report (and of its CSV).
class PilotReportRow {
  const PilotReportRow({
    required this.sessionId,
    this.participantCode = '',
    this.createdAt,
    this.status = '',
    this.endReason,
    this.path,
    this.protocolVersion,
    this.devicePlatform,
    this.deviceModel,
    this.userAgent,
    this.screen,
    this.camera,
    this.cameraLabel,
    this.estimator,
    this.synthetic = false,
    this.calibrationResidualPx,
    this.validationPassed,
    this.validationCorrectRatio,
    this.validationReasons = '',
    this.settingsVersion,
    this.quality = '',
    this.qualityReasons = '',
    this.stagesCompleted,
    this.stageDecisions = '',
    this.comfortMin,
    this.comfortMean,
    this.comfortLowCount,
    this.pauses,
    this.endedEarly,
    this.comprehensionShare,
    this.numberTaskShare,
    this.debrief = 'none',
    this.debriefAnswers = const {},
    this.observations = 0,
    this.observationsMajorOrStop = 0,
    this.referenceRecordings = 0,
  });

  final String sessionId;
  final String participantCode;
  final String? createdAt;
  final String status;
  final String? endReason;
  final String? path;
  final int? protocolVersion;
  final String? devicePlatform;
  final String? deviceModel;
  final String? userAgent;
  final String? screen;
  final String? camera;
  final String? cameraLabel;
  final String? estimator;
  final bool synthetic;
  final double? calibrationResidualPx;
  final bool? validationPassed;
  final double? validationCorrectRatio;

  /// Reasons joined with `;`.
  final String validationReasons;
  final int? settingsVersion;

  /// The grade: `ok`, `review` or `exclude`.
  final String quality;
  final String qualityReasons;
  final int? stagesCompleted;

  /// `0:advance;1:hold`.
  final String stageDecisions;
  final double? comfortMin;
  final double? comfortMean;
  final int? comfortLowCount;
  final int? pauses;
  final bool? endedEarly;
  final double? comprehensionShare;
  final double? numberTaskShare;

  /// `answered`, `skipped` or `none`.
  final String debrief;
  final Map<String, dynamic> debriefAnswers;
  final int observations;
  final int observationsMajorOrStop;
  final int referenceRecordings;

  factory PilotReportRow.fromJson(Map<String, dynamic> json) => PilotReportRow(
        sessionId: _str(json['session_id']),
        participantCode: _str(json['participant_code']),
        createdAt: _text(json['created_at']),
        status: _str(json['status']),
        endReason: _text(json['end_reason']),
        path: _text(json['path']),
        protocolVersion: _intOrNull(json['protocol_version']),
        devicePlatform: _text(json['device_platform']),
        deviceModel: _text(json['device_model']),
        userAgent: _text(json['user_agent']),
        screen: _text(json['screen']),
        camera: _text(json['camera']),
        cameraLabel: _text(json['camera_label']),
        estimator: _text(json['estimator']),
        synthetic: json['synthetic'] == true,
        calibrationResidualPx: _dbl(json['calibration_residual_px']),
        validationPassed: _boolOrNull(json['validation_passed']),
        validationCorrectRatio: _dbl(json['validation_correct_ratio']),
        validationReasons: _str(json['validation_reasons']),
        settingsVersion: _intOrNull(json['settings_version']),
        quality: _str(json['quality']),
        qualityReasons: _str(json['quality_reasons']),
        stagesCompleted: _intOrNull(json['stages_completed']),
        stageDecisions: _str(json['stage_decisions']),
        comfortMin: _dbl(json['comfort_min']),
        comfortMean: _dbl(json['comfort_mean']),
        comfortLowCount: _intOrNull(json['comfort_low_count']),
        pauses: _intOrNull(json['pauses']),
        endedEarly: _boolOrNull(json['ended_early']),
        comprehensionShare: _dbl(json['comprehension_share']),
        numberTaskShare: _dbl(json['number_task_share']),
        debrief: _str(json['debrief'], 'none'),
        debriefAnswers: _map(json['debrief_answers']),
        observations: _int(json['observations']),
        observationsMajorOrStop: _int(json['observations_major_or_stop']),
        referenceRecordings: _int(json['reference_recordings']),
      );
}

/// One device platform in the pilot report.
class ReportDeviceRow {
  const ReportDeviceRow({
    this.devicePlatform = 'unknown',
    this.sessions = 0,
    this.validated = 0,
    this.validationPassed = 0,
    this.qualityOk = 0,
  });

  final String devicePlatform;
  final int sessions;
  final int validated;
  final int validationPassed;
  final int qualityOk;

  factory ReportDeviceRow.fromJson(Map<String, dynamic> json) => ReportDeviceRow(
        devicePlatform: _str(json['device_platform'], 'unknown'),
        sessions: _int(json['sessions']),
        validated: _int(json['validated']),
        validationPassed: _int(json['validation_passed']),
        qualityOk: _int(json['quality_ok']),
      );
}

/// Answer counts (and the mean of a scale) of one debrief question.
class DebriefQuestionStat {
  const DebriefQuestionStat({
    required this.key,
    this.type = '',
    this.prompt = '',
    this.answered = 0,
    this.counts = const {},
    this.mean,
  });

  final String key;
  final String type;
  final String prompt;
  final int answered;

  /// Answer value (`3`, `true`, an option) -> how many gave it. Free-text
  /// questions have no counts; their answers are the report's comments.
  final Map<String, int> counts;
  final double? mean;

  factory DebriefQuestionStat.fromJson(Map<String, dynamic> json) =>
      DebriefQuestionStat(
        key: _str(json['key']),
        type: _str(json['type']),
        prompt: _str(json['prompt']),
        answered: _int(json['answered']),
        counts: _counts(json['counts']),
        mean: _dbl(json['mean']),
      );
}

/// A free-text debrief answer under the research code.
class DebriefComment {
  const DebriefComment({
    this.sessionId = '',
    this.participantCode = '',
    this.key = '',
    this.text = '',
  });

  final String sessionId;
  final String participantCode;
  final String key;
  final String text;

  factory DebriefComment.fromJson(Map<String, dynamic> json) => DebriefComment(
        sessionId: _str(json['session_id']),
        participantCode: _str(json['participant_code']),
        key: _str(json['key']),
        text: _str(json['text']),
      );
}

class ReportDebrief {
  const ReportDebrief({
    this.answered = 0,
    this.skipped = 0,
    this.questions = const [],
    this.comments = const [],
  });

  final int answered;
  final int skipped;
  final List<DebriefQuestionStat> questions;
  final List<DebriefComment> comments;

  factory ReportDebrief.fromJson(Object? value) {
    final json = _map(value);
    return ReportDebrief(
      answered: _int(json['answered']),
      skipped: _int(json['skipped']),
      questions: [
        for (final m in _maps(json['questions'])) DebriefQuestionStat.fromJson(m),
      ],
      comments: [
        for (final m in _maps(json['comments'])) DebriefComment.fromJson(m),
      ],
    );
  }
}

class ReportObservations {
  const ReportObservations({
    this.total = 0,
    this.byCategory = const {},
    this.items = const [],
  });

  final int total;

  /// category -> severity -> count.
  final Map<String, Map<String, int>> byCategory;
  final List<Observation> items;

  factory ReportObservations.fromJson(Object? value) {
    final json = _map(value);
    return ReportObservations(
      total: _int(json['total']),
      byCategory: {
        for (final e in _map(json['by_category']).entries) e.key: _counts(e.value),
      },
      items: Observation.listFromJson(json['items']),
    );
  }
}

/// `GET /studies/{id}/pilot/report`.
class PilotReport {
  const PilotReport({
    this.studyId = '',
    this.settings = const SettingsSnapshot(),
    this.sessions = 0,
    this.participants = 0,
    this.skippedSynthetic = 0,
    this.includesSynthetic = false,
    this.validated = 0,
    this.validationPassed = 0,
    this.quality = const QualityCounts(),
    this.endedEarly = 0,
    this.comfortStageValues = const {},
    this.byDevice = const [],
    this.debrief = const ReportDebrief(),
    this.observations = const ReportObservations(),
    this.rows = const [],
    this.note = '',
  });

  final String studyId;
  final SettingsSnapshot settings;
  final int sessions;
  final int participants;
  final int skippedSynthetic;
  final bool includesSynthetic;

  /// Sessions with a validation, and how many of them passed.
  final int validated;
  final int validationPassed;
  final QualityCounts quality;
  final int endedEarly;

  /// Comfort value ("1".."5") -> how many stage answers.
  final Map<String, int> comfortStageValues;
  final List<ReportDeviceRow> byDevice;
  final ReportDebrief debrief;
  final ReportObservations observations;
  final List<PilotReportRow> rows;
  final String note;

  factory PilotReport.fromJson(Map<String, dynamic> json) {
    final validation = _map(json['validation']);
    return PilotReport(
      studyId: _str(json['study_id']),
      settings: SettingsSnapshot.fromJson(json['settings']),
      sessions: _int(json['sessions']),
      participants: _int(json['participants']),
      skippedSynthetic: _int(json['skipped_synthetic']),
      includesSynthetic: json['includes_synthetic'] == true,
      validated: _int(validation['validated']),
      validationPassed: _int(validation['passed']),
      quality: QualityCounts.fromJson(json['quality']),
      endedEarly: _int(json['ended_early']),
      comfortStageValues: _counts(json['comfort_stage_values']),
      byDevice: [
        for (final m in _maps(json['by_device'])) ReportDeviceRow.fromJson(m),
      ],
      debrief: ReportDebrief.fromJson(json['debrief']),
      observations: ReportObservations.fromJson(json['observations']),
      rows: [for (final m in _maps(json['rows'])) PilotReportRow.fromJson(m)],
      note: _str(json['note']),
    );
  }
}

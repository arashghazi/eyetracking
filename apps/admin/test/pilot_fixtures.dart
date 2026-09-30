import 'package:eyetracking_core/eyetracking_core.dart';

/// Wire-shaped data of the step 6 endpoints, parsed by the real models so the
/// screens see exactly what the server would send.

Map<String, dynamic> settingsJson({
  double correct = 0.8,
  double uncertain = 0.2,
  double ratio = 2,
  double conf = 0.5,
  int points = 9,
  double qUncertain = 0.2,
  double qMissing = 0.2,
}) =>
    {
      'validation_min_correct': correct,
      'validation_max_uncertain': uncertain,
      'min_region_to_error_ratio': ratio,
      'gaze_conf_threshold': conf,
      'calibration_points': points,
      'allow_continue_without_validation': true,
      'quality_max_uncertain_share': qUncertain,
      'quality_max_missing_share': qMissing,
    };

Map<String, dynamic> distJson(double base, {int n = 5}) => {
      'n': n,
      'min': base,
      'p25': base + 0.1,
      'median': base + 0.2,
      'p75': base + 0.3,
      'p90': base + 0.4,
      'max': base + 0.5,
    };

/// A review where lowering the minimum correct share from 0.8 to 0.7 turns
/// session 11 from "not passed / review" into "passed / ok".
ThresholdReview sampleReview({bool includeSynthetic = false}) =>
    ThresholdReview.fromJson({
      'current': {'version': 1, 'values': settingsJson()},
      'candidate': {
        'values': settingsJson(correct: 0.7),
        'changes': {'validation_min_correct': 0.7},
      },
      'sessions': 3,
      'skipped_synthetic': includeSynthetic ? 0 : 2,
      'includes_synthetic': includeSynthetic,
      'validated_sessions': 2,
      'validation_pass': {'current': 1, 'candidate': 2},
      'quality': {
        'current': {'ok': 1, 'review': 1, 'exclude': 1},
        'candidate': {'ok': 2, 'review': 0, 'exclude': 1},
      },
      'changed_sessions': 1,
      'distributions': {
        'correct_ratio': distJson(0.5),
        'uncertain_ratio': {'n': 0},
        'size_ratio': distJson(1),
        'residual_px_median': distJson(20),
        'uncertain_share': distJson(0),
        'missing_share': distJson(0),
      },
      'by_device': [
        {
          'device_platform': 'windows',
          'sessions': 2,
          'validated': 2,
          'pass_current': 1,
          'pass_candidate': 2,
        },
        {
          'device_platform': 'android',
          'sessions': 1,
          'validated': 0,
          'pass_current': 0,
          'pass_candidate': 0,
        },
      ],
      'rows': [
        {
          'session_id': 11,
          'participant_code': 'P-001',
          'created_at': '2026-09-29T10:00:00',
          'device_platform': 'windows',
          'synthetic': false,
          'settings_version': 1,
          'validation_current': {
            'passed': false,
            'reasons': ['correct_ratio_below_0.8'],
          },
          'validation_candidate': {'passed': true, 'reasons': []},
          'quality_current': {
            'grade': 'review',
            'reasons': ['validation_not_passed'],
          },
          'quality_candidate': {'grade': 'ok', 'reasons': []},
          'changed': true,
          'metrics': {
            'correct_ratio': 0.75,
            'uncertain_ratio': 0.1,
            'size_ratio': 2.4,
            'residual_px_median': 22.5,
          },
        },
        {
          'session_id': 12,
          'participant_code': 'P-002',
          'created_at': '2026-09-29T11:00:00',
          'device_platform': 'windows',
          'synthetic': false,
          'settings_version': 1,
          'validation_current': {'passed': true, 'reasons': []},
          'validation_candidate': {'passed': true, 'reasons': []},
          'quality_current': {'grade': 'ok', 'reasons': []},
          'quality_candidate': {'grade': 'ok', 'reasons': []},
          'changed': false,
          'metrics': {
            'correct_ratio': 0.95,
            'uncertain_ratio': 0.05,
            'size_ratio': 3.1,
            'residual_px_median': 15.5,
          },
        },
        {
          'session_id': 13,
          'participant_code': 'P-003',
          'created_at': '2026-09-29T12:00:00',
          'device_platform': 'android',
          'synthetic': includeSynthetic,
          'settings_version': null,
          'validation_current': null,
          'validation_candidate': null,
          'quality_current': {'grade': 'exclude', 'reasons': ['no_calibration']},
          'quality_candidate': {'grade': 'exclude', 'reasons': ['no_calibration']},
          'changed': false,
          'metrics': {
            'correct_ratio': null,
            'uncertain_ratio': null,
            'size_ratio': null,
            'residual_px_median': null,
          },
        },
      ],
      'notes': [
        'gaze_conf_threshold changes how each sample is classified; it applies to new sessions only.',
        'Nothing is saved. A researcher decides and saves a new settings version with a rationale.',
      ],
    });

const activeSessions = [
  ActiveSession(
    sessionId: '21',
    participantCode: 'P-001',
    status: 'running',
    createdAt: '2026-09-30T09:00:00',
    devicePlatform: 'windows',
    protocolId: '4',
    lastEvent: ActiveLastEvent(type: 'segment_start', tMs: 1500),
  ),
  ActiveSession(
    sessionId: '22',
    participantCode: 'P-002',
    status: 'created',
    createdAt: '2026-09-30T09:10:00',
  ),
];

LiveStatus liveStatus({
  String sessionId = '21',
  String status = 'running',
  bool synthetic = false,
  int? lastSampleTMs = 61250,
  int observations = 0,
  double? secondsSinceLastEvent = 3.5,
  String? endReason,
  String? currentSegment = 'practice',
  bool paused = false,
}) =>
    LiveStatus.fromJson({
      'session_id': int.parse(sessionId),
      'participant_code': sessionId == '21' ? 'P-001' : 'P-002',
      'status': status,
      'synthetic': synthetic,
      'estimator': synthetic ? 'synthetic-0' : 'l2cs-net',
      'calibration_valid': true,
      'validation': {'passed': true, 'reasons': []},
      'current_segment': currentSegment,
      'paused': paused,
      'pauses': 2,
      'stage_index': 1,
      'last_stage_result': {
        'stage_index': 0,
        'decision': 'advance',
        'reason': 'all_good',
        'comfort_value': 4,
        'correct_ratio': 0.9,
      },
      'samples_total': 480,
      'last_sample_t_ms': lastSampleTMs,
      'recent_window_ms': 10000,
      'recent': {
        'samples': 40,
        'valid_share': 0.85,
        'regions': {
          'eye': 10,
          'mouth': 5,
          'face_other': 15,
          'outside': 4,
          'uncertain': 6,
        },
      },
      'recent_events': [
        {'t_ms': 59000, 'type': 'segment_start', 'payload': {'segment': 'practice'}},
        {'t_ms': 60000, 'type': 'pause', 'payload': {}},
        {'t_ms': 61000, 'type': 'resume', 'payload': {}},
      ],
      'seconds_since_last_event': secondsSinceLastEvent,
      'observations': observations,
      'end_reason': endReason,
      'note': 'Live view for the supervisor.',
    });

Observation observation(
  String id, {
  String session = '21',
  String category = 'comfort',
  String severity = 'info',
  String text = 'Looked away twice',
  int? tMs,
}) =>
    Observation(
      id: id,
      sessionId: session,
      authorId: 7,
      category: category,
      severity: severity,
      text: text,
      tMs: tMs,
      createdAt: '2026-09-30T09:30:00',
    );

const comparisonCaveats = [
  'The webcam side used a synthetic estimator; agreement numbers mean nothing.',
  'The time alignment was estimated from this same data, which makes the agreement optimistic.',
  "This session's regional validation did not pass.",
];

ReferenceComparison sampleComparison({bool caveats = true}) =>
    ReferenceComparison.fromJson({
      'tolerance_ms': 40,
      'webcam_samples': 500,
      'paired_classified': 400,
      'webcam_uncertain_while_reference_valid': 30,
      'reference_invalid': 20,
      'no_reference_in_time': 50,
      'distance_px': distJson(10, n: 400),
      'bias_px': {'x': 3.2, 'y': -1.4},
      'region_agreement': 0.82,
      'cohen_kappa': 0.61,
      'confusion': {
        'rows_webcam_columns_reference': {
          'eye': {'eye': 100, 'mouth': 5, 'face_other': 10, 'outside': 0},
          'mouth': {'eye': 4, 'mouth': 60, 'face_other': 6, 'outside': 0},
          'face_other': {'eye': 12, 'mouth': 8, 'face_other': 150, 'outside': 3},
          'outside': {'eye': 0, 'mouth': 0, 'face_other': 2, 'outside': 40},
        },
      },
      'eye_region': {'precision': 0.87, 'recall': 0.86},
      'segments': [
        {'segment': 'baseline', 'pairs': 100, 'webcam_eye_share': 0.3, 'reference_eye_share': 0.35},
        {'segment': 'post', 'pairs': 90, 'webcam_eye_share': null, 'reference_eye_share': null},
      ],
      'note': 'Agreement for this session on this computer only.',
      'recording': {
        'id': 901,
        'session_id': 21,
        'source': 'Tobii Pro Spark',
        'settings': {'alignment': 'estimated_from_data', 'estimated_shift_ms': -120},
        'sample_count': 5000,
        'valid_count': 4800,
        'uploaded_by': 7,
        'created_at': '2026-09-30T10:00:00',
      },
      'session': {
        'id': 21,
        'participant_code': 'P-001',
        'estimator': 'synthetic-0',
        'gaze_model_version': 'v1',
        'synthetic': true,
        'validation_passed': false,
        'screen': {'w': 1920, 'h': 1080, 'dpr': 1},
      },
      'caveats': caveats ? comparisonCaveats : <String>[],
    });

const existingRecording = ReferenceRecording(
  id: '901',
  sessionId: '21',
  source: 'Tobii Pro Spark',
  settings: {'alignment': 'estimated_from_data', 'estimated_shift_ms': -120},
  sampleCount: 5000,
  validCount: 4800,
  uploadedBy: 7,
  createdAt: '2026-09-30T10:00:00',
);

Map<String, dynamic> reportRow(
  int id,
  String code, {
  String quality = 'ok',
  bool? passed = true,
  String debrief = 'answered',
  bool synthetic = false,
}) =>
    {
      'session_id': id,
      'participant_code': code,
      'created_at': '2026-09-29T10:00:00',
      'status': 'ended',
      'end_reason': id.isEven ? 'ended_early' : 'completed',
      'path': 'gradual_face',
      'protocol_version': 2,
      'device_platform': 'windows',
      'device_model': null,
      'user_agent': 'UA',
      'screen': '1920x1080@1',
      'camera': '640x480',
      'camera_label': 'Cam',
      'estimator': synthetic ? 'synthetic-0' : 'l2cs-net',
      'synthetic': synthetic,
      'calibration_residual_px': 22.5,
      'validation_passed': passed,
      'validation_correct_ratio': 0.9,
      'validation_reasons': '',
      'settings_version': 2,
      'quality': quality,
      'quality_reasons': quality == 'ok' ? '' : 'validation_not_passed',
      'stages_completed': 3,
      'stage_decisions': '0:advance;1:hold',
      'comfort_min': 3,
      'comfort_mean': 3.5,
      'comfort_low_count': 0,
      'pauses': 1,
      'ended_early': id.isEven,
      'comprehension_share': 0.8,
      'number_task_share': null,
      'debrief': debrief,
      'debrief_answers': debrief == 'answered' ? {'comfort_overall': 4} : {},
      'observations': 2,
      'observations_major_or_stop': 1,
      'reference_recordings': 1,
    };

PilotReport sampleReport({bool includeSynthetic = false}) =>
    PilotReport.fromJson({
      'study_id': 1,
      'settings': {'version': 3, 'values': settingsJson()},
      'sessions': 2,
      'participants': 2,
      'skipped_synthetic': includeSynthetic ? 0 : 1,
      'includes_synthetic': includeSynthetic,
      'validation': {'validated': 2, 'passed': 1},
      'quality': {'ok': 1, 'review': 1, 'exclude': 0},
      'ended_early': 1,
      'comfort_stage_values': {'1': 0, '3': 2, '5': 1},
      'by_device': [
        {
          'device_platform': 'windows',
          'sessions': 2,
          'validated': 2,
          'validation_passed': 1,
          'quality_ok': 1,
        },
      ],
      'debrief': {
        'answered': 1,
        'skipped': 1,
        'questions': [
          {
            'key': 'comfort_overall',
            'type': 'scale',
            'prompt': 'How comfortable did you feel?',
            'answered': 1,
            'counts': {'4': 1},
            'mean': 4.0,
          },
          {
            'key': 'anything_uncomfortable',
            'type': 'yes_no',
            'prompt': 'Was anything uncomfortable?',
            'answered': 1,
            'counts': {'true': 1},
          },
          {
            'key': 'one_change',
            'type': 'text',
            'prompt': 'If you could change one thing?',
            'answered': 1,
            'counts': {},
          },
        ],
        'comments': [
          {
            'session_id': 21,
            'participant_code': 'P-001',
            'key': 'one_change',
            'text': 'A brighter room please',
          },
        ],
      },
      'observations': {
        'total': 2,
        'by_category': {
          'comfort': {'info': 1},
          'technical': {'major': 1},
        },
        'items': [
          {
            'id': 1,
            'session_id': 21,
            'author_id': 7,
            'category': 'comfort',
            'severity': 'info',
            'text': 'Looked away twice',
            't_ms': null,
            'created_at': '2026-09-29T10:05:00',
            'participant_code': 'P-001',
          },
          {
            'id': 2,
            'session_id': 21,
            'author_id': 7,
            'category': 'technical',
            'severity': 'major',
            'text': 'Camera lost the face twice',
            't_ms': 4200,
            'created_at': '2026-09-29T10:06:00',
            'participant_code': 'P-001',
          },
        ],
      },
      'rows': [
        reportRow(21, 'P-001'),
        reportRow(22, 'P-002', quality: 'review', passed: false, debrief: 'skipped'),
      ],
      'note': 'Pilot summary for the research team.',
    });

DebriefForm sampleForm({int version = 2, bool enabled = true, bool saved = true}) =>
    DebriefForm.fromJson({
      'version': version,
      'enabled': enabled,
      'saved': saved,
      'questions': [
        {
          'key': 'comfort_overall',
          'type': 'scale',
          'prompt': 'How comfortable did you feel?',
          'scale_max': 5,
          'labels': ['Very uncomfortable', 'Uncomfortable', 'Neutral', 'Comfortable', 'Very comfortable'],
          'required': true,
        },
        {
          'key': 'anything_uncomfortable',
          'type': 'yes_no',
          'prompt': 'Was anything uncomfortable?',
          'required': false,
        },
        {
          'key': 'room',
          'type': 'choice',
          'prompt': 'Which room was it?',
          'options': ['Lab', 'Office'],
          'required': false,
        },
        {
          'key': 'one_change',
          'type': 'text',
          'prompt': 'If you could change one thing?',
          'required': false,
        },
      ],
    });

final settingsHistory = [
  SettingsVersion.fromJson({
    'version': 2,
    'values': settingsJson(correct: 0.7, conf: 0.6),
    'rationale': 'Too many fails on old laptops',
    'changed_by': 7,
    'created_at': '2026-09-29T10:00:00',
  }),
  SettingsVersion.fromJson({
    'version': 1,
    'values': settingsJson(),
    'rationale': 'Defaults; no change recorded yet',
    'changed_by': null,
    'created_at': null,
  }),
];

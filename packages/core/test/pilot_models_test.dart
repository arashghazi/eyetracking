import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> settingsJson({double correct = 0.8}) => {
      'validation_min_correct': correct,
      'validation_max_uncertain': 0.2,
      'min_region_to_error_ratio': 2,
      'gaze_conf_threshold': 0.5,
      'calibration_points': 9,
      'allow_continue_without_validation': true,
      'quality_max_uncertain_share': 0.2,
      'quality_max_missing_share': 0.25,
    };

Map<String, dynamic> dist(double base) => {
      'n': 4,
      'min': base,
      'p25': base + 0.1,
      'median': base + 0.2,
      'p75': base + 0.3,
      'p90': base + 0.4,
      'max': base + 0.5,
    };

Map<String, dynamic> reviewJson() => {
      'current': {'version': 3, 'values': settingsJson()},
      'candidate': {
        'values': settingsJson(correct: 0.7),
        'changes': {'validation_min_correct': 0.7},
      },
      'sessions': 3,
      'skipped_synthetic': 2,
      'includes_synthetic': false,
      'validated_sessions': 2,
      'validation_pass': {'current': 1, 'candidate': 2},
      'quality': {
        'current': {'ok': 1, 'review': 1, 'exclude': 1},
        'candidate': {'ok': 2, 'review': 0, 'exclude': 1},
      },
      'changed_sessions': 1,
      'distributions': {
        'correct_ratio': dist(0.5),
        'uncertain_ratio': {'n': 0},
        'size_ratio': dist(1),
        'residual_px_median': dist(20),
        'uncertain_share': dist(0),
        'missing_share': dist(0),
      },
      'by_device': [
        {
          'device_platform': 'windows',
          'sessions': 2,
          'validated': 2,
          'pass_current': 1,
          'pass_candidate': 2,
        },
      ],
      'rows': [
        {
          'session_id': 11,
          'participant_code': 'P-001',
          'created_at': '2026-09-29T10:00:00',
          'device_platform': 'windows',
          'synthetic': false,
          'settings_version': 2,
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
          'created_at': null,
          'device_platform': null,
          'synthetic': true,
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
      'notes': ['gaze_conf_threshold applies to new sessions only.'],
    };

Map<String, dynamic> liveJson() => {
      'session_id': 21,
      'participant_code': 'P-003',
      'status': 'running',
      'synthetic': true,
      'estimator': 'synthetic-0',
      'calibration_valid': true,
      'validation': {'passed': false, 'reasons': ['uncertain_ratio_above_0.2']},
      'current_segment': 'practice',
      'paused': true,
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
      'last_sample_t_ms': 61250,
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
        {'t_ms': 60000, 'type': 'pause', 'payload': {'reason': 'user'}},
        {'t_ms': 61000, 'type': 'note', 'payload': null},
      ],
      'seconds_since_last_event': 3.5,
      'observations': 2,
      'end_reason': null,
      'note': 'Live view for the supervisor.',
    };

Map<String, dynamic> comparisonJson() => {
      'tolerance_ms': 40,
      'webcam_samples': 500,
      'paired_classified': 400,
      'webcam_uncertain_while_reference_valid': 30,
      'reference_invalid': 20,
      'no_reference_in_time': 50,
      'distance_px': dist(10),
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
        'id': 5,
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
        'participant_code': 'P-003',
        'estimator': 'synthetic-0',
        'gaze_model_version': 'v1',
        'synthetic': true,
        'validation_passed': false,
        'screen': {'w': 1920, 'h': 1080, 'dpr': 1},
      },
      'caveats': [
        'The webcam side used a synthetic estimator; agreement numbers mean nothing.',
        "This session's regional validation did not pass.",
      ],
    };

Map<String, dynamic> reportRowJson(int id, {String code = 'P-001'}) => {
      'session_id': id,
      'participant_code': code,
      'created_at': '2026-09-29T10:00:00',
      'status': 'ended',
      'end_reason': 'completed',
      'path': 'gradual_face',
      'protocol_version': 2,
      'device_platform': 'windows',
      'device_model': null,
      'user_agent': 'UA',
      'screen': '1920x1080@1',
      'camera': '640x480',
      'camera_label': 'Cam',
      'estimator': 'l2cs',
      'synthetic': false,
      'calibration_residual_px': 22.5,
      'validation_passed': true,
      'validation_correct_ratio': 0.9,
      'validation_reasons': '',
      'settings_version': 2,
      'quality': 'ok',
      'quality_reasons': '',
      'stages_completed': 3,
      'stage_decisions': '0:advance;1:hold',
      'comfort_min': 3,
      'comfort_mean': 3.5,
      'comfort_low_count': 0,
      'pauses': 1,
      'ended_early': false,
      'comprehension_share': 0.8,
      'number_task_share': null,
      'debrief': 'answered',
      'debrief_answers': {'comfort_overall': 4},
      'observations': 2,
      'observations_major_or_stop': 1,
      'reference_recordings': 1,
    };

Map<String, dynamic> reportJson() => {
      'study_id': 1,
      'settings': {'version': 3, 'values': settingsJson()},
      'sessions': 2,
      'participants': 2,
      'skipped_synthetic': 1,
      'includes_synthetic': false,
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
            'prompt': 'How comfortable?',
            'answered': 1,
            'counts': {'4': 1},
            'mean': 4.0,
          },
          {
            'key': 'anything',
            'type': 'yes_no',
            'prompt': 'Anything?',
            'answered': 1,
            'counts': {'true': 1},
          },
        ],
        'comments': [
          {'session_id': 21, 'participant_code': 'P-001', 'key': 'one_change', 'text': 'Brighter room'},
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
            'category': 'technical',
            'severity': 'major',
            'text': 'Camera lost twice',
            't_ms': 4200,
            'created_at': '2026-09-29T10:05:00',
            'participant_code': 'P-001',
          },
        ],
      },
      'rows': [reportRowJson(21), reportRowJson(22, code: 'P-002')],
      'note': 'Pilot summary for the research team.',
    };

void main() {
  group('settings values and versions', () {
    test('SettingsValues reads the eight values and defaults what is missing', () {
      final v = SettingsValues.fromJson(settingsJson());
      expect(v.validationMinCorrect, 0.8);
      expect(v.minRegionToErrorRatio, 2.0);
      expect(v.calibrationPoints, 9);
      expect(v.allowContinueWithoutValidation, isTrue);
      expect(v.qualityMaxMissingShare, 0.25);
      expect(v.toJson().keys, SettingsValues.keys);

      const d = SettingsValues();
      final empty = SettingsValues.fromJson(null);
      expect(empty.toJson(), d.toJson());
      expect(SettingsValues.fromJson({'calibration_points': null}).calibrationPoints, 9);
    });

    test('changesFrom lists only what differs, in the display order', () {
      final now = SettingsValues.fromJson(
        {...settingsJson(correct: 0.7), 'calibration_points': 12},
      );
      final before = SettingsValues.fromJson(settingsJson());
      final changes = now.changesFrom(before);
      expect([for (final c in changes) c.key],
          ['validation_min_correct', 'calibration_points']);
      expect(changes.first.label, 'Minimum correct share');
      expect(changes.first.text, '0.8 -> 0.7');
      expect(changes.last.text, '9 -> 12');
      expect(now.changesFrom(null), isEmpty,
          reason: 'the oldest version has nothing to compare with');
      expect(before.changesFrom(before), isEmpty);
    });

    test('formatSettingValue drops floating-point noise', () {
      expect(formatSettingValue(0.8), '0.8');
      expect(formatSettingValue(2.0), '2');
      expect(formatSettingValue(0.30000000000000004), '0.3');
      expect(formatSettingValue(true), 'Yes');
      expect(formatSettingValue(false), 'No');
      expect(formatSettingValue(null), '-');
      expect(settingLabel('quality_max_missing_share'), 'Quality: maximum missing share');
      expect(settingLabel('other'), 'other');
    });

    test('SettingsVersion allows a null date and author (the synthesized entry)', () {
      final list = SettingsVersion.listFromJson([
        {
          'version': 2,
          'values': settingsJson(correct: 0.7),
          'rationale': 'Too strict',
          'changed_by': 7,
          'created_at': '2026-09-29T10:00:00',
        },
        {
          'version': 1,
          'values': settingsJson(),
          'rationale': 'Defaults; no change recorded yet',
          'changed_by': null,
          'created_at': null,
        },
      ]);
      expect(list.first.version, 2);
      expect(list.first.changedBy, 7);
      expect(list.first.rationale, 'Too strict');
      expect(list.last.changedBy, isNull);
      expect(list.last.createdAt, isNull);
      expect(SettingsVersion.listFromJson(null), isEmpty);
    });

    test('MeasurementSettings carries the version and the quality thresholds', () {
      final s = MeasurementSettings.fromJson({...settingsJson(), 'version': 4});
      expect(s.version, 4);
      expect(s.qualityMaxMissingShare, 0.25);
      expect(s.qualityMaxUncertainShare, 0.2);
      // The form edits six values; the version and the quality thresholds are
      // not sent from there.
      expect(s.toJson().keys, hasLength(6));
      expect(s.toJson().containsKey('version'), isFalse);
      expect(MeasurementSettings.fromJson({}).version, 1);
      // A version is not a value: equal values are equal settings.
      expect(
        MeasurementSettings.fromJson({...settingsJson(), 'version': 9}),
        s,
      );
      expect(
        MeasurementSettings.fromJson({...settingsJson(), 'quality_max_missing_share': 0.5}),
        isNot(s),
      );
    });
  });

  group('threshold review', () {
    test('parses every field', () {
      final r = ThresholdReview.fromJson(reviewJson());
      expect(r.current.version, 3);
      expect(r.current.values.validationMinCorrect, 0.8);
      expect(r.candidateValues.validationMinCorrect, 0.7);
      expect(r.changes, {'validation_min_correct': 0.7});
      expect(r.sessions, 3);
      expect(r.skippedSynthetic, 2);
      expect(r.includesSynthetic, isFalse);
      expect(r.validatedSessions, 2);
      expect(r.validationPass.current, 1);
      expect(r.validationPass.candidate, 2);
      expect(r.qualityCurrent.review, 1);
      expect(r.qualityCandidate.ok, 2);
      expect(r.qualityCurrent.total, 3);
      expect(r.qualityCandidate.count(QualityGrade.exclude), 1);
      expect(r.changedSessions, 1);
      expect(r.distributions.keys, ThresholdReview.distributionKeys);
      expect(r.distributions['correct_ratio']!.median, closeTo(0.7, 1e-9));
      expect(r.distributions['uncertain_ratio']!.isEmpty, isTrue);
      expect(r.distributions['uncertain_ratio']!.min, isNull);
      expect(r.byDevice.single.passCandidate, 2);
      expect(r.notes.single, contains('new sessions only'));
    });

    test('rows keep nulls for a session without a validation', () {
      final r = ThresholdReview.fromJson(reviewJson());
      final changed = r.rows.first;
      expect(changed.sessionId, '11');
      expect(changed.participantCode, 'P-001');
      expect(changed.changed, isTrue);
      expect(changed.validationCurrent!.passed, isFalse);
      expect(changed.validationCurrent!.reasons, ['correct_ratio_below_0.8']);
      expect(changed.validationCandidate!.passed, isTrue);
      expect(changed.qualityCurrent!.grade, 'review');
      expect(changed.qualityCandidate!.isOk, isTrue);
      expect(changed.metrics.correctRatio, 0.75);
      expect(changed.settingsVersion, 2);

      final plain = r.rows.last;
      expect(plain.synthetic, isTrue);
      expect(plain.validationCurrent, isNull);
      expect(plain.validationCandidate, isNull);
      expect(plain.createdAt, isNull);
      expect(plain.devicePlatform, isNull);
      expect(plain.settingsVersion, isNull);
      expect(plain.metrics.correctRatio, isNull);
      expect(plain.metrics.residualPxMedian, isNull);
      expect(plain.qualityCurrent!.isExcluded, isTrue);
    });

    test('an empty answer parses to empty defaults', () {
      final r = ThresholdReview.fromJson(const {});
      expect(r.rows, isEmpty);
      expect(r.notes, isEmpty);
      expect(r.distributions, isEmpty);
      expect(r.current.version, 1);
      expect(r.validationPass.current, 0);
    });
  });

  group('observations', () {
    test('parse, with the research code in the report', () {
      final o = Observation.fromJson({
        'id': 3,
        'session_id': 21,
        'author_id': 7,
        'category': 'ux',
        'severity': 'stop',
        'text': 'Participant asked to stop',
        't_ms': null,
        'created_at': '2026-09-29T10:05:00',
        'participant_code': 'P-004',
      });
      expect(o.id, '3');
      expect(o.sessionId, '21');
      expect(o.category, 'ux');
      expect(o.severity, 'stop');
      expect(o.isMajorOrStop, isTrue);
      expect(o.tMs, isNull);
      expect(o.participantCode, 'P-004');
      expect(Observation.fromJson(const {}).category, 'other');
      expect(Observation.fromJson(const {}).severity, 'info');
    });

    test('the request leaves t_ms out when it is about the whole session', () {
      expect(
        const ObservationRequest(category: 'comfort', text: 'Fidgeting').toJson(),
        {'category': 'comfort', 'severity': 'info', 'text': 'Fidgeting'},
      );
      expect(
        const ObservationRequest(
          category: 'technical',
          severity: 'major',
          text: 'Lost face',
          tMs: 4200,
        ).toJson(),
        {'category': 'technical', 'severity': 'major', 'text': 'Lost face', 't_ms': 4200},
      );
    });

    test('constants and labels', () {
      expect(ObservationCategory.all, [
        'comfort',
        'comprehension',
        'technical',
        'ux',
        'protocol',
        'other',
      ]);
      expect(ObservationSeverity.all, ['info', 'minor', 'major', 'stop']);
      expect(observationCategoryLabel('ux'), 'Usability');
      expect(observationSeverityLabel('stop'), 'Stop');
      expect(kMaxObservationChars, 2000);
    });
  });

  group('live monitor', () {
    test('ActiveSession reads the last event or null', () {
      final list = ActiveSession.listFromJson([
        {
          'session_id': 21,
          'participant_code': 'P-003',
          'status': 'running',
          'created_at': '2026-09-30T09:00:00',
          'device_platform': 'windows',
          'protocol_id': 4,
          'last_event': {'type': 'segment_start', 't_ms': 1500, 'created_at': '2026-09-30T09:00:02'},
        },
        {
          'session_id': 22,
          'participant_code': 'P-004',
          'status': 'created',
          'created_at': '2026-09-30T09:10:00',
          'device_platform': null,
          'protocol_id': null,
          'last_event': null,
        },
      ]);
      expect(list.first.sessionId, '21');
      expect(list.first.protocolId, '4');
      expect(list.first.lastEvent!.type, 'segment_start');
      expect(list.first.lastEvent!.tMs, 1500);
      expect(list.last.lastEvent, isNull);
      expect(list.last.devicePlatform, isNull);
    });

    test('LiveStatus parses every field', () {
      final s = LiveStatus.fromJson(liveJson());
      expect(s.sessionId, '21');
      expect(s.participantCode, 'P-003');
      expect(s.status, 'running');
      expect(s.isEnded, isFalse);
      expect(s.synthetic, isTrue);
      expect(s.estimator, 'synthetic-0');
      expect(s.calibrationValid, isTrue);
      expect(s.validation!.passed, isFalse);
      expect(s.validation!.reasons, ['uncertain_ratio_above_0.2']);
      expect(s.currentSegment, 'practice');
      expect(s.paused, isTrue);
      expect(s.pauses, 2);
      expect(s.stageIndex, 1);
      expect(s.lastStageResult!.decision, 'advance');
      expect(s.lastStageResult!.comfortValue, 4);
      expect(s.lastStageResult!.correctRatio, 0.9);
      expect(s.samplesTotal, 480);
      expect(s.lastSampleTMs, 61250);
      expect(s.recentWindowMs, 10000);
      expect(s.recent.samples, 40);
      expect(s.recent.validShare, 0.85);
      expect(s.recent.region('eye'), 10);
      expect(s.recent.region('uncertain'), 6);
      expect(s.recent.region('nowhere'), 0);
      expect(s.recentEvents.map((e) => e.type), ['pause', 'note']);
      expect(s.recentEvents.first.payload, {'reason': 'user'});
      expect(s.recentEvents.last.payload, isEmpty, reason: 'a null payload is empty');
      expect(s.secondsSinceLastEvent, 3.5);
      expect(s.observations, 2);
      expect(s.endReason, isNull);
      expect(s.note, startsWith('Live view'));
    });

    test('a session without data yet has nulls, and an ended one says so', () {
      final s = LiveStatus.fromJson({
        'session_id': 5,
        'participant_code': 'P-009',
        'status': 'ended',
        'synthetic': false,
        'estimator': null,
        'calibration_valid': false,
        'validation': null,
        'current_segment': null,
        'paused': false,
        'pauses': 0,
        'stage_index': null,
        'last_stage_result': null,
        'samples_total': 0,
        'last_sample_t_ms': null,
        'recent_window_ms': 10000,
        'recent': {'samples': 0, 'valid_share': null, 'regions': {}},
        'recent_events': [],
        'seconds_since_last_event': null,
        'observations': 0,
        'end_reason': 'completed',
        'note': '',
      });
      expect(s.isEnded, isTrue);
      expect(s.endReason, 'completed');
      expect(s.validation, isNull);
      expect(s.lastStageResult, isNull);
      expect(s.stageIndex, isNull);
      expect(s.lastSampleTMs, isNull);
      expect(s.recent.validShare, isNull);
      expect(s.secondsSinceLastEvent, isNull);
      expect(LiveStatus.fromJson(const {}).recentWindowMs, 10000);
    });
  });

  group('debrief form', () {
    final formJson = {
      'version': 2,
      'enabled': true,
      'saved': true,
      'questions': [
        {
          'key': 'comfort_overall',
          'type': 'scale',
          'prompt': 'How comfortable?',
          'scale_max': 5,
          'labels': ['a', 'b', 'c', 'd', 'e'],
          'required': true,
        },
        {'key': 'anything', 'type': 'yes_no', 'prompt': 'Anything?', 'required': false},
        {
          'key': 'room',
          'type': 'choice',
          'prompt': 'Which room?',
          'options': ['A', 'B'],
          'required': false,
        },
        {'key': 'one_change', 'type': 'text', 'prompt': 'One change?', 'required': false},
      ],
    };

    test('parses the four question types', () {
      final f = DebriefForm.fromJson(formJson);
      expect(f.version, 2);
      expect(f.enabled, isTrue);
      expect(f.saved, isTrue);
      expect(f.questions.map((q) => q.type), DebriefQuestionType.all);
      final scale = f.questions.first;
      expect(scale.scaleMax, 5);
      expect(scale.labels, hasLength(5));
      expect(scale.required, isTrue);
      expect(f.questions[2].options, ['A', 'B']);
      expect(f.questions[1].scaleMax, isNull);
    });

    test('an unsaved form is version 0 and off', () {
      final f = DebriefForm.fromJson({'version': 0, 'enabled': false, 'saved': false, 'questions': []});
      expect(f.version, 0);
      expect(f.saved, isFalse);
      expect(DebriefForm.fromJson(const {}).questions, isEmpty);
    });

    test('toJson sends only the fields of the type and round-trips', () {
      final f = DebriefForm.fromJson(formJson);
      final json = [for (final q in f.questions) q.toJson()];
      expect(json[0].keys, containsAll(['scale_max', 'labels']));
      expect(json[0].containsKey('options'), isFalse);
      expect(json[1].keys, ['key', 'type', 'prompt', 'required']);
      expect(json[2]['options'], ['A', 'B']);
      expect(json[2].containsKey('scale_max'), isFalse);
      expect(json[3].keys, ['key', 'type', 'prompt', 'required']);
      expect(DebriefQuestion.listFromJson(json).map((q) => q.toJson()), json);
    });

    test('the key pattern follows the contract', () {
      expect(DebriefQuestion.keyPattern.hasMatch('comfort_1'), isTrue);
      expect(DebriefQuestion.keyPattern.hasMatch('1comfort'), isFalse);
      expect(DebriefQuestion.keyPattern.hasMatch('Comfort'), isFalse);
      expect(DebriefQuestion.keyPattern.hasMatch('a' * 40), isTrue);
      expect(DebriefQuestion.keyPattern.hasMatch('a' * 41), isFalse);
      expect(debriefQuestionTypeLabel('yes_no'), 'Yes / no');
    });
  });

  group('research eye tracker', () {
    test('a recording knows how it was aligned', () {
      final given = ReferenceRecording.fromJson({
        'id': 4,
        'session_id': 21,
        'source': 'Tobii',
        'settings': {'alignment': 'given_offset', 'time_unit': 'ms'},
        'sample_count': 100,
        'valid_count': 90,
        'uploaded_by': 7,
        'created_at': '2026-09-30T10:00:00',
      });
      expect(given.id, '4');
      expect(given.alignmentEstimated, isFalse);
      expect(given.estimatedShiftMs, isNull);
      expect(given.sampleCount, 100);
      expect(given.validCount, 90);

      final estimated = ReferenceRecording.fromJson({
        'id': 5,
        'settings': {'alignment': 'estimated_from_data', 'estimated_shift_ms': -120},
      });
      expect(estimated.alignmentEstimated, isTrue);
      expect(estimated.estimatedShiftMs, -120);
      expect(ReferenceRecording.listFromJson(null), isEmpty);
    });

    test('the import request leaves optional fields out and writes numbers plainly', () {
      final fields = const ReferenceImportRequest(
        source: '  Tobii Pro Spark ',
        timeColumn: 'time',
        xColumn: 'gaze_x',
        yColumn: 'gaze_y',
      ).toFields();
      expect(fields, {
        'source': 'Tobii Pro Spark',
        'time_column': 'time',
        'x_column': 'gaze_x',
        'y_column': 'gaze_y',
        'time_unit': 'ms',
        'offset': '0',
        'coord_space': 'css_px',
        'origin_x': '0',
        'origin_y': '0',
        'auto_align_window_ms': '0',
      });

      final full = const ReferenceImportRequest(
        source: 'EyeLink',
        timeColumn: 't',
        xColumn: 'x',
        yColumn: 'y',
        validColumn: 'ok',
        validValues: 'yes,1',
        timeUnit: ReferenceTimeUnit.us,
        offset: 1500.5,
        coordSpace: ReferenceCoordSpace.norm,
        originX: -3,
        originY: 4.25,
        delimiter: '\t',
        autoAlignWindowMs: 2000,
      ).toFields();
      expect(full['valid_column'], 'ok');
      expect(full['valid_values'], 'yes,1');
      expect(full['time_unit'], 'us');
      expect(full['offset'], '1500.5');
      expect(full['coord_space'], 'norm');
      expect(full['origin_x'], '-3');
      expect(full['origin_y'], '4.25');
      expect(full['delimiter'], '\t');
      expect(full['auto_align_window_ms'], '2000');
    });

    test('the comparison parses the matrix, distances, bias, kappa and caveats', () {
      final c = ReferenceComparison.fromJson(comparisonJson());
      expect(c.toleranceMs, 40);
      expect(c.webcamSamples, 500);
      expect(c.pairedClassified, 400);
      expect(c.webcamUncertainWhileReferenceValid, 30);
      expect(c.referenceInvalid, 20);
      expect(c.noReferenceInTime, 50);
      expect(c.distancePx.n, 4);
      expect(c.distancePx.median, closeTo(10.2, 1e-9));
      expect(c.biasX, 3.2);
      expect(c.biasY, -1.4);
      expect(c.regionAgreement, 0.82);
      expect(c.cohenKappa, 0.61);
      expect(c.eyePrecision, 0.87);
      expect(c.eyeRecall, 0.86);
      expect(c.confusion.cell('eye', 'eye'), 100);
      expect(c.confusion.cell('face_other', 'eye'), 12);
      expect(c.confusion.cell('outside', 'face_other'), 2);
      expect(c.confusion.cell('eye', 'nowhere'), 0);
      expect(c.confusion.rowTotal('eye'), 115);
      expect(c.confusion.columnTotal('eye'), 116);
      expect(c.confusion.total, 400);
      expect(c.segments.first.segment, 'baseline');
      expect(c.segments.first.webcamEyeShare, 0.3);
      expect(c.segments.last.webcamEyeShare, isNull);
      expect(c.recording!.source, 'Tobii Pro Spark');
      expect(c.recording!.alignmentEstimated, isTrue);
      expect(c.session.participantCode, 'P-003');
      expect(c.session.synthetic, isTrue);
      expect(c.session.validationPassed, isFalse);
      expect(c.session.screen['w'], 1920);
      expect(c.caveats, hasLength(2));
      expect(c.note, contains('this computer only'));
    });

    test('an empty comparison has null shares instead of zeros', () {
      final c = ReferenceComparison.fromJson({
        'tolerance_ms': 40,
        'distance_px': {'n': 0},
        'bias_px': {'x': null, 'y': null},
        'region_agreement': null,
        'cohen_kappa': null,
        'confusion': {'rows_webcam_columns_reference': {}},
        'eye_region': {'precision': null, 'recall': null},
        'segments': [],
        'caveats': [],
      });
      expect(c.distancePx.isEmpty, isTrue);
      expect(c.biasX, isNull);
      expect(c.regionAgreement, isNull);
      expect(c.cohenKappa, isNull);
      expect(c.eyePrecision, isNull);
      expect(c.confusion.total, 0);
      expect(c.recording, isNull);
      expect(c.caveats, isEmpty);
    });
  });

  group('pilot report', () {
    test('parses summary, devices, debrief, observations and rows', () {
      final r = PilotReport.fromJson(reportJson());
      expect(r.settings.version, 3);
      expect(r.sessions, 2);
      expect(r.participants, 2);
      expect(r.skippedSynthetic, 1);
      expect(r.includesSynthetic, isFalse);
      expect(r.validated, 2);
      expect(r.validationPassed, 1);
      expect(r.quality.ok, 1);
      expect(r.quality.review, 1);
      expect(r.endedEarly, 1);
      expect(r.comfortStageValues, {'1': 0, '3': 2, '5': 1});
      expect(r.byDevice.single.devicePlatform, 'windows');
      expect(r.byDevice.single.qualityOk, 1);
      expect(r.note, contains('Pilot summary'));

      expect(r.debrief.answered, 1);
      expect(r.debrief.skipped, 1);
      expect(r.debrief.questions.first.mean, 4.0);
      expect(r.debrief.questions.first.counts, {'4': 1});
      expect(r.debrief.questions.last.mean, isNull);
      expect(r.debrief.comments.single.text, 'Brighter room');
      expect(r.debrief.comments.single.participantCode, 'P-001');

      expect(r.observations.total, 2);
      expect(r.observations.byCategory['technical'], {'major': 1});
      expect(r.observations.items.single.participantCode, 'P-001');
      expect(r.observations.items.single.tMs, 4200);
    });

    test('a row keeps every column and its nulls', () {
      final row = PilotReport.fromJson(reportJson()).rows.first;
      expect(row.sessionId, '21');
      expect(row.participantCode, 'P-001');
      expect(row.status, 'ended');
      expect(row.endReason, 'completed');
      expect(row.path, 'gradual_face');
      expect(row.protocolVersion, 2);
      expect(row.deviceModel, isNull);
      expect(row.screen, '1920x1080@1');
      expect(row.estimator, 'l2cs');
      expect(row.synthetic, isFalse);
      expect(row.calibrationResidualPx, 22.5);
      expect(row.validationPassed, isTrue);
      expect(row.validationCorrectRatio, 0.9);
      expect(row.settingsVersion, 2);
      expect(row.quality, 'ok');
      expect(row.stagesCompleted, 3);
      expect(row.stageDecisions, '0:advance;1:hold');
      expect(row.comfortMin, 3);
      expect(row.comfortMean, 3.5);
      expect(row.pauses, 1);
      expect(row.endedEarly, isFalse);
      expect(row.comprehensionShare, 0.8);
      expect(row.numberTaskShare, isNull);
      expect(row.debrief, 'answered');
      expect(row.debriefAnswers, {'comfort_overall': 4});
      expect(row.observations, 2);
      expect(row.observationsMajorOrStop, 1);
      expect(row.referenceRecordings, 1);
    });

    test('an empty answer parses to defaults', () {
      final r = PilotReport.fromJson(const {});
      expect(r.rows, isEmpty);
      expect(r.sessions, 0);
      expect(r.debrief.questions, isEmpty);
      expect(r.observations.items, isEmpty);
      expect(r.comfortStageValues, isEmpty);
      expect(PilotReportRow.fromJson(const {}).debrief, 'none');
    });
  });

  group('multipart fields', () {
    test('uploadFile sends the text fields before the file', () async {
      late List<int> bytes;
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient.streaming((request, body) async {
          bytes = await body.expand((c) => c).toList();
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'id': 1}))),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await api.uploadFile(
        '/studies/1/sessions/2/reference',
        bytes: utf8.encode('t,x,y\n0,1,2\n'),
        filename: 'export.csv',
        contentType: 'text/csv',
        fields: {'source': 'Tobii "Pro"', 'time_unit': 'ms', 'delimiter': '\t'},
      );
      final text = utf8.decode(bytes);
      expect(text, contains('name="source"\r\n\r\nTobii "Pro"\r\n'));
      expect(text, contains('name="time_unit"\r\n\r\nms\r\n'));
      expect(text, contains('name="delimiter"\r\n\r\n\t\r\n'));
      expect(text.indexOf('name="source"'), lessThan(text.indexOf('name="file"')));
      expect(text, contains('name="file"; filename="export.csv"'));
      expect(text, contains('t,x,y\n0,1,2\n'));
    });
  });
}

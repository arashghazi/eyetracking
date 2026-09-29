import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeasurementSettings', () {
    test('parses the contract shape and round-trips', () {
      final s = MeasurementSettings.fromJson({
        'validation_min_correct': 0.8,
        'validation_max_uncertain': 0.2,
        'min_region_to_error_ratio': 2.0,
        'gaze_conf_threshold': 0.5,
        'calibration_points': 9,
        'allow_continue_without_validation': true,
      });
      expect(s, MeasurementSettings.defaults);
      expect(MeasurementSettings.fromJson(s.toJson()), s);
      expect(s.toJson().keys, hasLength(6));
    });

    test('validates ratios, ratio >= 1 and 5..16 points', () {
      expect(MeasurementSettings.defaults.validate(), isEmpty);
      final bad = const MeasurementSettings(
        validationMinCorrect: 1.2,
        validationMaxUncertain: -0.1,
        minRegionToErrorRatio: 0.5,
        gazeConfThreshold: 2,
        calibrationPoints: 4,
      ).validate();
      expect(bad.keys, {
        'validation_min_correct',
        'validation_max_uncertain',
        'min_region_to_error_ratio',
        'gaze_conf_threshold',
        'calibration_points',
      });
      expect(
        const MeasurementSettings(calibrationPoints: 17).validate().keys,
        ['calibration_points'],
      );
      expect(const MeasurementSettings(calibrationPoints: 16).validate(), isEmpty);
      expect(const MeasurementSettings(calibrationPoints: 5).validate(), isEmpty);
    });
  });

  group('RawGazeSample', () {
    test('serialises exactly the raw sample fields', () {
      const sample = RawGazeSample(
        tMs: 1200,
        faceDetected: true,
        faceBox: Box(10, 20, 30, 40),
        faceConf: 0.9,
        yawDeg: 1.5,
        pitchDeg: -2,
        gazeConf: 0.7,
        frameW: 640,
        frameH: 480,
        modelId: 'm',
      );
      expect(sample.toJson(), {
        't_ms': 1200,
        'face_detected': true,
        'face_box': [10.0, 20.0, 30.0, 40.0],
        'face_conf': 0.9,
        'yaw_deg': 1.5,
        'pitch_deg': -2.0,
        'gaze_conf': 0.7,
        'frame_w': 640,
        'frame_h': 480,
      });
    });

    test('parses a sample without a face', () {
      final s = RawGazeSample.fromJson({
        't_ms': 5,
        'face_detected': false,
        'face_box': null,
        'face_conf': 0,
        'yaw_deg': null,
        'pitch_deg': null,
        'gaze_conf': 0,
        'frame_w': 640,
        'frame_h': 480,
        'model_id': 'stub',
      });
      expect(s.faceDetected, isFalse);
      expect(s.faceBox, isNull);
      expect(s.hasFace, isFalse);
      expect(s.modelId, 'stub');
    });
  });

  test('StimulusLayout serialises regions as [x, y, w, h]', () {
    const layout = StimulusLayout(
      screen: ScreenInfo(w: 1280, h: 720, dpr: 1.25),
      faceBox: Box(400, 100, 300, 420),
      eyeRegion: Box(400, 163, 300, 147),
      mouthRegion: Box(400, 331, 300, 168),
    );
    final json = layout.toJson();
    expect(json['screen'], {'w': 1280, 'h': 720, 'dpr': 1.25});
    expect(json['face_box'], [400.0, 100.0, 300.0, 420.0]);
    expect(StimulusLayout.fromJson(json).eyeRegion, layout.eyeRegion);
  });

  group('SessionSummary', () {
    final json = {
      'id': 7,
      'status': 'ended',
      'created_at': '2026-09-29T08:00:00',
      'ended_at': '2026-09-29T08:05:00',
      'synthetic': true,
      'calibration_valid': true,
      'calibration': {
        'residual_px_median': 88.5,
        'residual_px_p90': 140.0,
        'points': 9,
      },
      'validation': {
        'passed': false,
        'correct_ratio': 0.5,
        'uncertain_ratio': 0.3,
        'size_ratio': 1.4,
        'reasons': ['too_many_uncertain'],
      },
      'coverage': {
        'total_ms': 30000,
        'classifiable_ms': 24000,
        'uncertain_ms': 4000,
        'missing_ms': 2000,
      },
      'region_shares': {
        'eye': 0.1,
        'mouth': 0.2,
        'face_other': 0.4,
        'outside': 0.3,
      },
      'face_region_attention': {'share': 0.7},
      'eye_region_attention': {
        'evaluable': false,
        'share': null,
        'reason': 'Validation did not pass.',
      },
      'segments': [
        {'label': 'baseline', 'started_ms': 1000, 'ended_ms': 31000},
      ],
      'events_count': 4,
      'notes': ['synthetic estimator'],
    };

    test('parses every part of the contract', () {
      final s = SessionSummary.fromJson(json);
      expect(s.id, '7');
      expect(s.isEnded, isTrue);
      expect(s.synthetic, isTrue);
      expect(s.calibration!.residualPxMedian, 88.5);
      expect(s.validation!.passed, isFalse);
      expect(s.validation!.reasons, ['too_many_uncertain']);
      expect(s.coverage.classifiableShare, closeTo(0.8, 1e-9));
      expect(s.regionShares!.faceOther, 0.4);
      expect(s.faceRegionShare, 0.7);
      expect(s.eyeRegionAttention.evaluable, isFalse);
      expect(s.eyeRegionAttention.share, isNull);
      expect(s.eyeRegionAttention.reason, 'Validation did not pass.');
      expect(s.segments.single.endedMs, 31000);
      expect(s.eventsCount, 4);
      expect(s.notes, ['synthetic estimator']);
    });

    test('tolerates a bare summary', () {
      final s = SessionSummary.fromJson({'id': 1, 'status': 'created'});
      expect(s.calibration, isNull);
      expect(s.validation, isNull);
      expect(s.coverage.classifiableShare, isNull);
      expect(s.eyeRegionAttention.evaluable, isFalse);
    });
  });

  test('CalibrationResult and ValidationResult parse the contract', () {
    final c = CalibrationResult.fromJson({
      'calibration_id': 3,
      'residual_px_median': 75.0,
      'residual_px_p90': 120.0,
      'per_target': [
        {'x': 100, 'y': 80, 'n_valid': 11, 'err_px': 60.5},
      ],
      'accepted': false,
      'reasons': ['residual too high'],
    });
    expect(c.accepted, isFalse);
    expect(c.perTarget.single.errPx, 60.5);
    expect(c.reasons, ['residual too high']);

    final v = ValidationResult.fromJson({
      'validation_id': 4,
      'passed': false,
      'correct_ratio': 0.6,
      'uncertain_ratio': 0.1,
      'size_ratio': 2.5,
      'reasons': ['correct share below 80 %'],
      'targets': [
        {
          'region': 'eye',
          'x': 500,
          'y': 300,
          'n': 14,
          'majority': 'face_other',
          'correct': false,
          'uncertain_share': 0.07,
        },
      ],
    });
    expect(v.passed, isFalse);
    expect(v.targets.single.majority, 'face_other');
    expect(v.targets.single.correct, isFalse);
  });

  test('admin models parse list item, detail and samples page', () {
    final item = SessionListItem.fromJson({
      'id': 9,
      'participant_code': 'P-001',
      'status': 'ended',
      'created_at': '2026-09-29T08:00:00',
      'ended_at': null,
      'synthetic': true,
      'device_platform': 'web',
      'calibration_residual_px': 90.0,
      'validation_passed': null,
      'coverage': {
        'total_ms': 1000,
        'classifiable_ms': 500,
        'uncertain_ms': 400,
        'missing_ms': 100,
      },
      'eye_region_attention': {
        'evaluable': false,
        'share': null,
        'reason': 'synthetic',
      },
    });
    expect(item.validationPassed, isNull);
    expect(item.coverage.classifiableShare, 0.5);
    expect(item.eyeRegionAttention.reason, 'synthetic');

    final detail = SessionDetail.fromJson({
      'id': 9,
      'status': 'ended',
      'participant_code': 'P-001',
      'device': {'platform': 'web'},
      'screen': {'w': 1280, 'h': 720, 'dpr': 1},
      'camera': {'label': 'Cam', 'w': 640, 'h': 480},
      'gaze_model': {'model_id': 'stub', 'model_version': '0', 'synthetic': true},
      'validation': {
        'passed': true,
        'correct_ratio': 0.9,
        'uncertain_ratio': 0.05,
        'size_ratio': 3,
        'reasons': [],
        'targets': [
          {
            'region': 'mouth',
            'x': 1,
            'y': 2,
            'n': 10,
            'majority': 'mouth',
            'correct': true,
            'uncertain_share': 0,
          },
        ],
      },
      'events': [
        {'t_ms': 1000, 'type': 'segment_start', 'payload': {'segment': 'baseline'}},
        {'t_ms': 2000, 'type': 'pause'},
      ],
    });
    expect(detail.participantCode, 'P-001');
    expect(detail.screen!.w, 1280);
    expect(detail.summary.validation!.targets.single.region, 'mouth');
    expect(detail.validationTargets.single.region, 'mouth');
    expect(detail.events, hasLength(2));
    expect(detail.events.first.payload, {'segment': 'baseline'});
    expect(detail.events.last.payload, isNull);

    final page = SamplesPage.fromJson({
      'total': 250,
      'items': [
        {
          't_ms': 100,
          'x': 10.5,
          'y': 20.5,
          'conf': 0.8,
          'valid': true,
          'region': 'eye',
          'segment': 'baseline',
        },
      ],
    });
    expect(page.total, 250);
    expect(page.items.single.region, 'eye');
  });

  test('SessionDetail accepts validation_targets next to validation', () {
    final detail = SessionDetail.fromJson({
      'id': 9,
      'status': 'ended',
      'end_reason': 'ended_early',
      'validation': {'passed': true},
      'validation_targets': [
        {
          'region': 'outside',
          'x': 5,
          'y': 6,
          'n': 8,
          'majority': 'outside',
          'correct': true,
          'uncertain_share': 0,
          'counts': {'outside': 8},
        },
      ],
    });
    expect(detail.validationTargets.single.region, 'outside');
    expect(detail.summary.endReason, 'ended_early');
    expect(sessionOutcomeLabel('ended', 'ended_early'), 'Ended early');
    expect(sessionOutcomeLabel('ended', 'completed'), 'Completed');
    expect(sessionOutcomeLabel('running', null), 'In progress');
  });

  test('request bodies match the contract', () {
    final body = const SessionCreateRequest(
      device: DeviceInfo(platform: 'web', userAgent: 'UA'),
      screen: ScreenInfo(w: 1280, h: 720, dpr: 2),
      camera: CameraInfo(label: 'Cam', w: 640, h: 480),
      gazeModel: GazeInfo(modelId: 'm', modelVersion: '1', synthetic: true),
    ).toJson();
    expect(body, {
      'device': {'platform': 'web', 'user_agent': 'UA'},
      'screen': {'w': 1280, 'h': 720, 'dpr': 2.0},
      'camera': {'label': 'Cam', 'w': 640, 'h': 480},
      'gaze_model': {'model_id': 'm', 'model_version': '1', 'synthetic': true},
    });
    expect(
      const CameraCheckRequest(
        faceDetected: true,
        faceConf: 0.8,
        lightingOk: true,
        frameW: 640,
        frameH: 480,
      ).toJson(),
      {
        'face_detected': true,
        'face_conf': 0.8,
        'lighting_ok': true,
        'frame_w': 640,
        'frame_h': 480,
      },
    );
    expect(SessionEventType.cameraChanged.wire, 'camera_changed');
    expect(FrameSourceEvent.zoomChanged.wire, 'zoom_changed');
  });

  test('formatters', () {
    expect(formatPercent(0.428), '43 %');
    expect(formatPercent(null), '—');
    expect(formatDurationMs(12400), '12.4 s');
    expect(formatDurationMs(125000), '2:05 min');
    expect(formatClockMs(65432), '01:05.432');
  });
}

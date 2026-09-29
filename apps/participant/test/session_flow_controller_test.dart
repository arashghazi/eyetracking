
import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/domain/session_step.dart';
import 'package:participant_app/features/session/domain/stimulus_geometry.dart';

import 'session_kit.dart';

void main() {
  group('introduction', () {
    test('loads settings and gaze info, then creates the session', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final c = rig.controller;

      await c.loadIntro();
      expect(c.introReady, isTrue);
      expect(c.step, SessionStep.intro);
      expect(rig.repo.created, isEmpty, reason: 'nothing is created before Begin');

      await c.begin();

      expect(c.step, SessionStep.cameraCheck);
      expect(rig.frames.startCount, 1);
      final body = rig.repo.created.single.toJson();
      expect(body['device'], {'platform': 'web', 'user_agent': 'test-agent'});
      expect(body['screen'], {'w': 1440, 'h': 900, 'dpr': 1.0});
      expect(body['camera'], {'label': 'Fake camera', 'w': 640, 'h': 480});
      expect(body['gaze_model'], {
        'model_id': 'fake-model',
        'model_version': '0',
        'synthetic': false,
      });
    });

    test('a 403 shows the readiness reasons and stops the camera', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.createFailure = const ApiException(
        'Not ready to start a session.',
        statusCode: 403,
      );
      final c = rig.controller;

      await c.loadIntro();
      await c.begin();

      expect(c.step, SessionStep.intro);
      expect(c.session, isNull);
      expect(c.blockedReasons, [
        'Consent missing or outdated',
        'Demographics incomplete',
      ]);
      expect(rig.frames.isActive, isFalse);
    });

    test('a denied camera keeps the participant on the introduction', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.frames.startError = const FrameSourceException('Camera access was not allowed.');
      final c = rig.controller;

      await c.loadIntro();
      await c.begin();

      expect(c.step, SessionStep.intro);
      expect(c.error, 'Camera access was not allowed.');
      expect(rig.repo.created, isEmpty);
    });

    test('an unreachable gaze service is reported on the introduction', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.gaze.failure = const ApiException('Could not reach the gaze service.');
      await rig.controller.loadIntro();
      expect(rig.controller.introReady, isFalse);
      expect(rig.controller.error, 'Could not reach the gaze service.');
    });
  });

  group('camera check', () {
    test('passes when at least 3 of 5 frames have a confident face', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      var call = 0;
      rig.gaze.sampleBuilder = (t, w, h) {
        final face = call++ < 3;
        return RawGazeSample(
          tMs: t,
          faceDetected: face,
          faceConf: face ? 0.8 : 0,
          frameW: w,
          frameH: h,
        );
      };
      await rig.toCameraCheck();
      await rig.controller.runCameraCheck();

      expect(rig.gaze.estimateCalls, 5);
      final outcome = rig.controller.cameraOutcome!;
      expect(outcome.passed, isTrue);
      expect(outcome.framesWithFace, 3);
      final posted = rig.repo.cameraChecks.single;
      expect(posted.faceDetected, isTrue);
      expect(posted.lightingOk, isTrue);
      expect(posted.faceConf, closeTo(0.8, 1e-9));
      expect(posted.frameW, 640);
    });

    test('a low-confidence face does not count and a retry can pass', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.gaze.faceConf = 0.4;
      await rig.toCameraCheck();
      await rig.controller.runCameraCheck();

      expect(rig.controller.cameraOutcome!.passed, isFalse);
      expect(rig.repo.cameraChecks.single.faceDetected, isFalse);
      rig.controller.continueToCalibration();
      expect(rig.controller.step, SessionStep.cameraCheck,
          reason: 'cannot continue after a failed check');

      rig.gaze.faceConf = 0.9;
      await rig.controller.runCameraCheck();
      expect(rig.controller.cameraOutcome!.passed, isTrue);
      expect(rig.repo.cameraChecks, hasLength(2));
    });
  });

  group('calibration', () {
    test('collects exactly N targets and posts once', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.toCalibration();
      final c = rig.controller;

      await c.startCalibration();

      expect(rig.repo.calibrations, hasLength(1));
      final targets = rig.repo.calibrations.single;
      expect(targets, hasLength(9));
      expect(targets.every((t) => t.samples.isNotEmpty), isTrue);
      // 3 x 3 grid inset 10 % from the edges of a 1440 x 900 screen.
      expect({for (final t in targets) t.x}, {144.0, 720.0, 1296.0});
      expect({for (final t in targets) t.y}, {90.0, 450.0, 810.0});
      expect(c.phase, StepPhase.result);
      expect(c.calibration!.accepted, isTrue);
      // Samples are raw gaze samples as the gaze service returned them.
      expect(targets.first.samples.first.faceDetected, isTrue);
    });

    test('follows the configured number of points', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.settings = const MeasurementSettings(calibrationPoints: 5);
      await rig.toCalibration();
      await rig.controller.startCalibration();
      expect(rig.repo.calibrations.single, hasLength(5));

      final sixteen = calibrationTargets(16, const ScreenInfo(w: 1000, h: 800));
      expect(sixteen, hasLength(16));
      expect(sixteen.first.x, closeTo(100, 1e-6));
      expect(sixteen.first.y, closeTo(80, 1e-6));
      expect(sixteen.last.x, closeTo(900, 1e-6));
      expect(sixteen.last.y, closeTo(720, 1e-6));
      expect(calibrationTargets(7, const ScreenInfo(w: 1000, h: 800)), hasLength(7));
    });

    test('a calibration that is not accepted offers another try only', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.calibrationResult = const CalibrationResult(
        residualPxMedian: 190,
        accepted: false,
        reasons: ['Typical error is too large.'],
      );
      await rig.toCalibration();
      final c = rig.controller;
      await c.startCalibration();

      expect(c.calibration!.accepted, isFalse);
      c.continueToValidation();
      expect(c.step, SessionStep.calibration);

      rig.repo.calibrationResult = acceptedCalibration;
      await c.startCalibration();
      expect(rig.repo.calibrations, hasLength(2));
      c.continueToValidation();
      expect(c.step, SessionStep.validation);
    });

    test('nothing is posted when no picture could be analysed', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.toCalibration();
      rig.gaze.failure = const ApiException('Could not reach the gaze service.');
      await rig.controller.startCalibration();
      expect(rig.repo.calibrations, isEmpty);
      expect(rig.controller.error, contains('No pictures could be analysed'));
      expect(rig.controller.phase, StepPhase.idle);
    });
  });

  group('validation', () {
    test('targets follow the required order', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.throughCalibration();
      await rig.controller.startValidation();

      final posted = rig.repo.validations.single;
      expect([for (final t in posted.targets) t.region],
          ['eye', 'eye', 'eye', 'mouth', 'mouth', 'outside', 'outside']);
      final t = posted.targets;
      expect(t[0].x, lessThan(t[2].x), reason: 'eye-left before eye-centre');
      expect(t[2].x, lessThan(t[1].x), reason: 'eye-centre before eye-right');
      expect(t[3].x, lessThan(t[4].x), reason: 'mouth-left then mouth-right');
      expect(t[5].x, lessThan(t[6].x));
      expect(t[5].y, lessThan(t[6].y), reason: 'top-left then bottom-right');
      expect(t.every((x) => x.samples.isNotEmpty), isTrue);
      expect(rig.controller.phase, StepPhase.result);
    });

    test('layout: eye region is at least max(120 px, 3 x residual) and fits',
        () async {
      for (final (residual, screen) in [
        (80.0, const ScreenInfo(w: 1440, h: 900)),
        (30.0, const ScreenInfo(w: 1440, h: 900)),
        (45.0, const ScreenInfo(w: 1024, h: 768)),
      ]) {
        final rig = Rig(screen: screen);
        addTearDown(rig.dispose);
        rig.repo.calibrationResult = CalibrationResult(
          residualPxMedian: residual,
          accepted: true,
        );
        await rig.throughCalibration();
        await rig.controller.startValidation();

        final layout = rig.repo.validations.single.layout;
        final wanted = residual * 3 > 120 ? residual * 3 : 120;
        expect(layout.eyeRegion.h, greaterThanOrEqualTo(wanted),
            reason: 'residual $residual on ${screen.w}x${screen.h}');
        expect(layout.screen, screen);
        final whole = Box(0, 0, screen.w, screen.h);
        expect(whole.containsBox(layout.faceBox), isTrue);
        expect(layout.faceBox.containsBox(layout.eyeRegion), isTrue);
        expect(layout.faceBox.containsBox(layout.mouthRegion), isTrue);
        expect(layout.eyeRegion.bottom, lessThanOrEqualTo(layout.mouthRegion.y));
        // Eye region = 15 % to 50 % of the face height, mouth 55 % to 95 %.
        final f = layout.faceBox;
        expect(layout.eyeRegion.y, closeTo(f.y + 0.15 * f.h, 1e-6));
        expect(layout.eyeRegion.bottom, closeTo(f.y + 0.50 * f.h, 1e-6));
        expect(layout.mouthRegion.y, closeTo(f.y + 0.55 * f.h, 1e-6));
        expect(layout.mouthRegion.bottom, closeTo(f.y + 0.95 * f.h, 1e-6));
        // The face card sits below the control bar.
        expect(f.y, greaterThanOrEqualTo(kControlBarHeight));
        expect(rig.controller.faceLayout!.fits, isTrue);
        // Outside targets really are outside the face.
        final outside = rig.repo.validations.single.targets.skip(5);
        for (final o in outside) {
          expect(f.contains(o.x, o.y), isFalse);
        }
      }
    });

    test('on a small screen the card is capped and flagged', () {
      final r = buildFaceLayout(
        screen: const ScreenInfo(w: 800, h: 500),
        residualPx: 120,
      );
      expect(r.desiredEyeHeight, 360);
      expect(r.fits, isFalse);
      expect(const Box(0, 0, 800, 500).containsBox(r.layout.faceBox), isTrue);
      expect(r.layout.faceBox.y, greaterThanOrEqualTo(kControlBarHeight));
    });

    test('a failed validation offers recalibration or continuing without',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.validationResult = failedValidation;
      await rig.throughValidation();
      final c = rig.controller;

      expect(c.validation!.passed, isFalse);
      expect(c.allowContinueWithoutValidation, isTrue);
      c.continueToBaseline();
      expect(c.step, SessionStep.baseline);

      // Recalibrate goes back and clears the result.
      final again = Rig();
      addTearDown(again.dispose);
      again.repo.validationResult = failedValidation;
      await again.throughValidation();
      again.controller.recalibrate();
      expect(again.controller.step, SessionStep.calibration);
      expect(again.controller.validation, isNull);
      expect(again.controller.phase, StepPhase.idle);
    });

    test('continuing without validation is blocked when the study forbids it',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.settings =
          const MeasurementSettings(allowContinueWithoutValidation: false);
      rig.repo.validationResult = failedValidation;
      await rig.throughValidation();
      rig.controller.continueToBaseline();
      expect(rig.controller.step, SessionStep.validation);
    });
  });

  group('baseline', () {
    test('posts layout, segment start, batched samples, segment end and end',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.trackSteps();
      await rig.toBaseline();
      final c = rig.controller;

      await c.startBaseline();
      await until(() => c.step == SessionStep.summary && !c.busy,
          what: 'summary');

      final calls = rig.repo.calls;
      expect(calls.indexOf('layout:baseline'), lessThan(calls.indexOf('event:segment_start')));
      expect(calls.indexOf('event:segment_start'), lessThan(calls.indexOf('samples')));
      expect(rig.repo.eventTypes, [
        SessionEventType.segmentStart,
        SessionEventType.segmentEnd,
        SessionEventType.end,
      ]);
      expect(rig.repo.events.last.payload, {'reason': 'completed'});
      expect(rig.repo.layouts.single.segment, SessionSegmentName.baseline);
      expect(rig.repo.layouts.single.layout.faceBox,
          rig.repo.validations.single.layout.faceBox);

      final batches = rig.repo.sampleBatches;
      expect(batches.length, greaterThan(1));
      for (final b in batches.take(batches.length - 1)) {
        expect(b, hasLength(10));
      }
      expect(batches.last.length, inInclusiveRange(1, 10));
      expect(c.storedSamples, rig.repo.sampleCount);

      expect(c.summary, isNotNull);
      expect(rig.steps, [
        SessionStep.intro,
        SessionStep.cameraCheck,
        SessionStep.calibration,
        SessionStep.validation,
        SessionStep.baseline,
        SessionStep.summary,
      ]);
      expect(rig.frames.isActive, isFalse, reason: 'the camera closes at the end');
    });

    test('pause stops streaming and resume restarts it', () async {
      final rig = Rig(timing: const SessionTiming(
        countdownStep: Duration(milliseconds: 2),
        settle: Duration(milliseconds: 8),
        calibrationCapture: Duration(milliseconds: 40),
        validationCapture: Duration(milliseconds: 40),
        baseline: Duration(seconds: 30),
        progressTick: Duration(milliseconds: 10),
      ));
      addTearDown(rig.dispose);
      await rig.toBaseline();
      final c = rig.controller;

      await c.startBaseline();
      await until(() => rig.frames.streaming && rig.repo.sampleCount > 0,
          what: 'streaming');
      expect(c.phase, StepPhase.running);

      await c.pause();
      expect(c.phase, StepPhase.paused);
      expect(rig.frames.streaming, isFalse);
      expect(rig.frames.isActive, isFalse);
      expect(rig.repo.eventTypes.last, SessionEventType.pause);
      final postedWhilePaused = rig.repo.sampleCount;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(rig.repo.sampleCount, postedWhilePaused,
          reason: 'nothing is sent while paused');

      await c.resume();
      expect(c.phase, StepPhase.running);
      expect(rig.repo.eventTypes.last, SessionEventType.resume);
      await until(() => rig.frames.streaming, what: 'streaming again');
      expect(rig.frames.isActive, isTrue);
      await until(() => rig.repo.sampleCount > postedWhilePaused,
          what: 'samples after resume');
    });

    test('end sends ended_early once and shows the summary', () async {
      final rig = Rig(timing: const SessionTiming(
        countdownStep: Duration(milliseconds: 2),
        settle: Duration(milliseconds: 8),
        calibrationCapture: Duration(milliseconds: 40),
        validationCapture: Duration(milliseconds: 40),
        baseline: Duration(seconds: 30),
        progressTick: Duration(milliseconds: 10),
      ));
      addTearDown(rig.dispose);
      await rig.toBaseline();
      final c = rig.controller;
      await c.startBaseline();
      await until(() => rig.repo.sampleCount > 0, what: 'first samples');

      await c.endEarly();

      expect(c.step, SessionStep.summary);
      expect(c.isEnded, isTrue);
      final ends = rig.repo.events.where((e) => e.type == SessionEventType.end);
      expect(ends, hasLength(1));
      expect(ends.single.payload, {'reason': 'ended_early'});
      expect(rig.repo.eventTypes, isNot(contains(SessionEventType.segmentEnd)));
      expect(c.summary, isNotNull);
      expect(rig.frames.streaming, isFalse);
      final count = rig.repo.sampleCount;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rig.repo.sampleCount, count);
    });

    test('a camera change stops streaming and returns to calibration',
        () async {
      final rig = Rig(timing: const SessionTiming(
        countdownStep: Duration(milliseconds: 2),
        settle: Duration(milliseconds: 8),
        calibrationCapture: Duration(milliseconds: 40),
        validationCapture: Duration(milliseconds: 40),
        baseline: Duration(seconds: 30),
        progressTick: Duration(milliseconds: 10),
      ));
      addTearDown(rig.dispose);
      await rig.toBaseline();
      final c = rig.controller;
      await c.startBaseline();
      await until(() => rig.frames.streaming, what: 'streaming');

      rig.frames.emitEvent(FrameSourceEvent.cameraChanged);
      await until(
        () => rig.repo.eventTypes.contains(SessionEventType.cameraChanged),
        what: 'camera_changed event',
      );

      expect(c.phase, StepPhase.changed);
      expect(c.change, FrameSourceEvent.cameraChanged);
      expect(rig.frames.streaming, isFalse);
      final count = rig.repo.sampleCount;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rig.repo.sampleCount, count);

      c.recalibrate();
      expect(c.step, SessionStep.calibration);
      expect(c.phase, StepPhase.idle);
      expect(c.calibration, isNull);
      expect(c.change, isNull);
    });

    for (final (source, wire) in [
      (FrameSourceEvent.orientationChanged, SessionEventType.orientationChanged),
      (FrameSourceEvent.zoomChanged, SessionEventType.zoomChanged),
    ]) {
      test('${source.name} is reported to the server', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await rig.toCalibration();
        final started = rig.controller.startCalibration();
        await until(() => rig.controller.phase == StepPhase.capturing,
            what: 'capturing');

        rig.frames.emitEvent(source);
        await started;
        await until(() => rig.repo.eventTypes.contains(wire), what: '$wire');

        expect(rig.controller.phase, StepPhase.changed);
        expect(rig.repo.calibrations, isEmpty,
            reason: 'an interrupted calibration is never posted');
      });
    }

    test('the face-lost overlay appears after 1 s without a face', () async {
      final rig = Rig(autoFrames: false, timing: const SessionTiming(
        countdownStep: Duration(milliseconds: 2),
        settle: Duration(milliseconds: 8),
        calibrationCapture: Duration(milliseconds: 40),
        validationCapture: Duration(milliseconds: 40),
        baseline: Duration(seconds: 30),
        progressTick: Duration(milliseconds: 10),
      ));
      addTearDown(rig.dispose);
      // Auto frames off: calibration and validation need frames, so use the
      // automatic source for them and switch to hand-made frames afterwards.
      rig.frames.autoFrames = true;
      await rig.toBaseline();
      rig.frames.autoFrames = false;
      final c = rig.controller;

      await c.startBaseline();
      await until(() => rig.frames.streaming, what: 'streaming');
      Future<void> frame(int t, {required bool face}) async {
        rig.gaze.facePresent = face;
        rig.frames.emit(tMs: t);
        await settle();
        await settle();
      }

      await frame(100000, face: true);
      await frame(100400, face: false);
      await frame(100999, face: false);
      expect(c.faceLost, isFalse, reason: 'less than one second so far');
      expect(rig.repo.eventTypes, isNot(contains(SessionEventType.faceLost)));

      await frame(101000, face: false);
      expect(c.faceLost, isTrue);
      await until(() => rig.repo.eventTypes.contains(SessionEventType.faceLost),
          what: 'face_lost');
      expect(
        rig.repo.events.firstWhere((e) => e.type == SessionEventType.faceLost).tMs,
        101000,
      );

      await frame(101300, face: true);
      expect(c.faceLost, isFalse);
      await until(() => rig.repo.eventTypes.contains(SessionEventType.faceFound),
          what: 'face_found');
      expect(
        rig.repo.events.where((e) => e.type == SessionEventType.faceLost),
        hasLength(1),
        reason: 'the overlay event is sent once per loss',
      );
    });
  });

  group('pause before the baseline', () {
    test('pausing a calibration is local and returns to the instructions',
        () async {
      final rig = Rig(timing: const SessionTiming(
        countdownStep: Duration(milliseconds: 30),
        settle: Duration(milliseconds: 30),
        calibrationCapture: Duration(milliseconds: 60),
      ));
      addTearDown(rig.dispose);
      await rig.toCalibration();
      final c = rig.controller;
      final run = c.startCalibration();
      await until(() => c.canPause, what: 'a pausable phase');

      await c.pause();
      await run;

      expect(c.phase, StepPhase.paused);
      expect(rig.frames.streaming, isFalse);
      expect(rig.repo.calibrations, isEmpty);
      expect(rig.repo.eventTypes, isEmpty,
          reason: 'no server segment is running yet');

      await c.resume();
      expect(c.phase, StepPhase.idle);
      expect(c.step, SessionStep.calibration);
    });
  });

  group('summary', () {
    test('ending sends `end` with completed only if not already ended', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.toBaseline();
      await rig.controller.startBaseline();
      await until(() => rig.controller.summary != null, what: 'summary');
      expect(
        rig.repo.events.where((e) => e.type == SessionEventType.end),
        hasLength(1),
      );
      expect(rig.repo.summaryCalls, 1);
    });

    test('ending in the camera check leaves an ended session', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.toCameraCheck();
      await rig.controller.endEarly();
      expect(rig.controller.step, SessionStep.summary);
      expect(rig.repo.events.single.payload, {'reason': 'ended_early'});
    });
  });
}

import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/application/session_flow_controller.dart';
import 'package:participant_app/features/session/domain/session_step.dart';
import 'package:participant_app/features/session/presentation/session_flow_screen.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'session_kit.dart';

/// Pumps the flow screen around an already driven [controller].
Future<void> pumpFlow(WidgetTester tester, SessionFlowController controller) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: SessionFlowScreen(controller: controller),
  ));
  await tester.pump();
}

/// Runs real (not fake-clock) async work such as the timed capture.
Future<void> drive(WidgetTester tester, Future<void> Function() work) async {
  await tester.runAsync(work);
  await tester.pump();
}

void main() {
  group('home entry points', () {
    testWidgets('Start a session is disabled until the participant is ready',
        (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed(home: FakeHomeRepository(reasons: const [
        ReadinessReason.demographicsIncomplete,
      ]));
      await pumpApp(tester, bed);

      final button = tester.widget<FilledButton>(find.byKey(const Key('start-session')));
      expect(button.onPressed, isNull);
      expect(find.textContaining('Finish the steps above first'), findsOneWidget);
    });

    testWidgets('a ready participant can open the introduction', (tester) async {
      useWindow(tester, 800, 1000);
      await pumpApp(tester, TestBed());

      final button = find.byKey(const Key('start-session'));
      await tester.ensureVisible(button);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('You can pause or end at any time and come back later.'),
          findsOneWidget);
    });

    testWidgets('My sessions lists status and date', (tester) async {
      useWindow(tester, 800, 1200);
      final bed = TestBed();
      bed.sessions.mineList = const [
        SessionSummary(
          id: '5',
          status: SessionStatus.ended,
          endReason: EndReason.endedEarly,
          createdAt: '2026-09-28T09:15:00',
        ),
        SessionSummary(
          id: '4',
          status: SessionStatus.calibrated,
          createdAt: '2026-09-27T17:40:00',
          synthetic: true,
        ),
      ];
      await pumpApp(tester, bed);

      expect(find.text('My sessions'), findsOneWidget);
      expect(find.text('2026-09-28 09:15 UTC'), findsOneWidget);
      expect(find.text('Ended early'), findsOneWidget);
      expect(find.text('2026-09-27 17:40 UTC'), findsOneWidget);
      expect(find.text('Calibrated'), findsOneWidget);
      expect(find.text('Development'), findsOneWidget);
    });

    testWidgets('My sessions says so when there are none', (tester) async {
      useWindow(tester, 800, 1200);
      await pumpApp(tester, TestBed());
      expect(find.byKey(const Key('no-sessions')), findsOneWidget);
    });
  });

  group('introduction', () {
    testWidgets('states that the participant can pause or end at any time',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      await drive(tester, rig.controller.loadIntro);
      await pumpFlow(tester, rig.controller);

      expect(find.byKey(const Key('stop-sentence')), findsOneWidget);
      expect(find.text('You can pause or end at any time and come back later.'),
          findsOneWidget);
      for (final label in [
        'Camera check',
        'Calibration',
        'Validation',
        'Baseline',
        'Summary',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'step list shows $label');
      }
      expect(find.byKey(const Key('pause')), findsNothing);
      expect(find.byKey(const Key('end-session')), findsNothing);
    });

    testWidgets('a 403 shows the readiness reasons and a way back home',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.createFailure =
          const ApiException('Not ready.', statusCode: 403);
      await drive(tester, () async {
        await rig.controller.loadIntro();
        await rig.controller.begin();
      });
      await pumpFlow(tester, rig.controller);

      expect(find.byKey(const Key('session-blocked')), findsOneWidget);
      expect(find.text('•  Consent missing or outdated'), findsOneWidget);
      expect(find.text('•  Demographics incomplete'), findsOneWidget);
      expect(find.byKey(const Key('blocked-home')), findsOneWidget);
      expect(find.byKey(const Key('intro-begin')), findsNothing);
    });

    testWidgets('a development estimator is flagged on the introduction',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.gaze.gazeInfo = const GazeInfo(
        modelId: 'stub',
        modelVersion: '0',
        synthetic: true,
      );
      await drive(tester, rig.controller.loadIntro);
      await pumpFlow(tester, rig.controller);
      expect(find.byKey(const Key('intro-synthetic')), findsOneWidget);
    });
  });

  group('camera check', () {
    testWidgets('shows the preview and the positioning instruction',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      await drive(tester, rig.toCameraCheck);
      await pumpFlow(tester, rig.controller);

      expect(find.text('Position your face in the frame'), findsOneWidget);
      expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
      expect(find.byKey(const Key('camera-run')), findsOneWidget);
    });

    testWidgets('a failed check shows a clear retry', (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.gaze.facePresent = false;
      await drive(tester, () async {
        await rig.toCameraCheck();
        await rig.controller.runCameraCheck();
      });
      await pumpFlow(tester, rig.controller);

      expect(find.byKey(const Key('camera-failed')), findsOneWidget);
      expect(find.textContaining('could not see your face'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const Key('camera-continue')), findsNothing);
    });

    testWidgets('a single camera is named without a choice', (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      await drive(tester, rig.toCameraCheck);
      await pumpFlow(tester, rig.controller);
      expect(find.text('Camera: Fake camera'), findsOneWidget);
      expect(find.byKey(const Key('camera-select')), findsNothing);
    });

    testWidgets('with several cameras the participant chooses one',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig(cameras: const ['Virtual camera', 'HD Pro Webcam C920']);
      addTearDown(rig.dispose);
      await drive(tester, rig.toCameraCheck);
      await pumpFlow(tester, rig.controller);
      expect(find.byKey(const Key('camera-select')), findsOneWidget);
      expect(find.text('Virtual camera'), findsOneWidget);

      await tester.tap(find.byKey(const Key('camera-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HD Pro Webcam C920').last);
      await tester.pumpAndSettle();
      expect(rig.frames.activeCameraLabel, 'HD Pro Webcam C920');
      expect(find.text('HD Pro Webcam C920'), findsOneWidget);
    });
  });

  group('session controls', () {
    for (final target in [
      SessionStep.calibration,
      SessionStep.validation,
      SessionStep.baseline,
    ]) {
      testWidgets('Pause and End session are visible in ${target.name}',
          (tester) async {
        useWindow(tester, 800, 900);
        final rig = Rig();
        addTearDown(rig.dispose);
        await drive(tester, () async {
          switch (target) {
            case SessionStep.calibration:
              await rig.toCalibration();
            case SessionStep.validation:
              await rig.throughCalibration();
            default:
              await rig.toBaseline();
          }
        });
        await pumpFlow(tester, rig.controller);

        expect(rig.controller.step, target);
        expect(find.byKey(const Key('pause')), findsOneWidget);
        expect(find.byKey(const Key('end-session')), findsOneWidget);
        expect(find.byKey(const Key('step-list')), findsOneWidget);
      });
    }

    testWidgets('End session asks first, then shows the summary', (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      await drive(tester, rig.toCalibration);
      await pumpFlow(tester, rig.controller);

      await tester.tap(find.byKey(const Key('end-session')));
      await tester.pumpAndSettle();
      expect(find.text('End the session?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('end-cancel')));
      await tester.pumpAndSettle();
      expect(rig.controller.step, SessionStep.calibration);
      expect(rig.repo.events, isEmpty);

      await tester.tap(find.byKey(const Key('end-session')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('end-confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(rig.controller.step, SessionStep.summary);
      expect(rig.repo.events.single.payload, {'reason': 'ended_early'});
      expect(find.text('Session summary'), findsOneWidget);
    });

    testWidgets('a camera change asks to calibrate again', (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      await drive(tester, rig.toCalibration);
      await pumpFlow(tester, rig.controller);

      await tester.runAsync(() async {
        rig.frames.emitEvent(FrameSourceEvent.zoomChanged);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();

      expect(find.text('The camera or screen changed. Please calibrate again.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('back-to-calibration')));
      await tester.pump();
      expect(find.byKey(const Key('calibration-start')), findsOneWidget);
    });
  });

  group('calibration and validation results', () {
    testWidgets('calibration shows the residual in pixels', (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      await drive(tester, () async {
        await rig.toCalibration();
        await rig.controller.startCalibration();
      });
      await pumpFlow(tester, rig.controller);

      expect(find.text('Calibration accepted'), findsOneWidget);
      expect(find.textContaining('60 px'), findsOneWidget);
      expect(find.byKey(const Key('calibration-continue')), findsOneWidget);
    });

    testWidgets('a rejected calibration offers Try again', (tester) async {
      useWindow(tester, 800, 900);
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.calibrationResult = const CalibrationResult(
        residualPxMedian: 210,
        accepted: false,
        reasons: ['Typical error is too large.'],
      );
      await drive(tester, () async {
        await rig.toCalibration();
        await rig.controller.startCalibration();
      });
      await pumpFlow(tester, rig.controller);

      expect(find.text('Calibration not accepted'), findsOneWidget);
      expect(find.text('Typical error is too large.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const Key('calibration-continue')), findsNothing);
    });

    testWidgets('a failed validation shows reasons, the table and both options',
        (tester) async {
      useWindow(tester, 800, 1000);
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.validationResult = failedValidation;
      await drive(tester, rig.throughValidation);
      await pumpFlow(tester, rig.controller);

      expect(find.text('Validation not passed'), findsOneWidget);
      expect(find.text('Only 40 % of the dots were on target (80 % needed).'),
          findsOneWidget);
      expect(find.text('Too many samples were uncertain.'), findsOneWidget);
      expect(find.byKey(const Key('validation-table')), findsOneWidget);
      expect(find.text('Left eye'), findsOneWidget);
      expect(find.text('Rest of the face'), findsOneWidget);
      expect(find.text('Recalibrate'), findsOneWidget);
      expect(find.text('Continue without eye-level scoring'), findsOneWidget);
      expect(find.byKey(const Key('validation-continue')), findsNothing);

      await tester.tap(find.byKey(const Key('validation-continue-without')));
      await tester.pump();
      expect(rig.controller.step, SessionStep.baseline);
      expect(find.byKey(const Key('baseline-start')), findsOneWidget);
    });

    testWidgets('continue-without is hidden when the study forbids it',
        (tester) async {
      useWindow(tester, 800, 1000);
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.settings =
          const MeasurementSettings(allowContinueWithoutValidation: false);
      rig.repo.validationResult = failedValidation;
      await drive(tester, rig.throughValidation);
      await pumpFlow(tester, rig.controller);

      expect(find.text('Recalibrate'), findsOneWidget);
      expect(find.text('Continue without eye-level scoring'), findsNothing);
    });

    testWidgets('a passed validation continues to the baseline', (tester) async {
      useWindow(tester, 800, 1000);
      final rig = Rig();
      addTearDown(rig.dispose);
      await drive(tester, rig.throughValidation);
      await pumpFlow(tester, rig.controller);

      expect(find.text('Validation passed'), findsOneWidget);
      await tester.tap(find.byKey(const Key('validation-continue')));
      await tester.pump();
      expect(find.text('Baseline'), findsWidgets);
      expect(find.byKey(const Key('baseline-start')), findsOneWidget);
    });
  });

  group('baseline stimulus', () {
    testWidgets('shows the face without a gaze dot, then the face-lost overlay',
        (tester) async {
      useWindow(tester, 1000, 800);
      final rig = Rig(timing: const SessionTiming(
        countdownStep: Duration(milliseconds: 2),
        settle: Duration(milliseconds: 8),
        calibrationCapture: Duration(milliseconds: 40),
        validationCapture: Duration(milliseconds: 40),
        baseline: Duration(seconds: 30),
        progressTick: Duration(milliseconds: 10),
      ));
      addTearDown(rig.dispose);
      await drive(tester, rig.toBaseline);
      rig.frames.autoFrames = false;
      await pumpFlow(tester, rig.controller);

      await tester.runAsync(() async {
        await rig.controller.startBaseline();
        await until(() => rig.frames.streaming, what: 'streaming');
      });
      await tester.pump();
      expect(find.byKey(const Key('face-stimulus')), findsOneWidget);
      expect(find.byKey(const Key('target-dot')), findsNothing);
      expect(find.byKey(const Key('baseline-progress')), findsOneWidget);
      expect(find.text("We can't see your face"), findsNothing);

      await tester.runAsync(() async {
        rig.gaze.facePresent = true;
        rig.frames.emit(tMs: 50000);
        await settle();
        await settle();
        rig.gaze.facePresent = false;
        rig.frames.emit(tMs: 51100);
        await settle();
        await settle();
      });
      await tester.pump();
      expect(find.text("We can't see your face"), findsOneWidget);
      expect(find.byKey(const Key('target-dot')), findsNothing);
      // Tear down while the baseline is still running.
      await tester.runAsync(rig.controller.endEarly);
    });
  });

  group('stimulus stage geometry', () {
    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('dots are drawn at the pixel the server is told, ${width.toInt()} px',
          (tester) async {
        final height = width == 360 ? 700.0 : 800.0;
        useWindow(tester, width, height);
        final rig = Rig(
          screen: ScreenInfo(w: width, h: height),
          timing: const SessionTiming(
            countdownStep: Duration(milliseconds: 2),
            settle: Duration(milliseconds: 10),
            calibrationCapture: Duration(seconds: 60),
            validationCapture: Duration(seconds: 60),
            baseline: Duration(seconds: 60),
          ),
        );
        addTearDown(rig.dispose);

        // Calibration: first dot is 10 % in from the left and top edges.
        await tester.runAsync(() async {
          await rig.toCalibration();
          unawaited(rig.controller.startCalibration());
          await until(
            () =>
                rig.controller.phase == StepPhase.capturing &&
                rig.controller.stage == TargetStage.capturing,
            what: 'the first calibration dot',
          );
        });
        await pumpFlow(tester, rig.controller);
        final dot = tester.getCenter(find.byKey(const Key('target-dot')));
        expect(dot.dx, closeTo(width * 0.10, 0.01));
        expect(dot.dy, closeTo(height * 0.10, 0.01));
        expect(find.byKey(const Key('face-stimulus')), findsNothing,
            reason: 'calibration shows dots only');
        expect(find.byKey(const Key('pause')), findsOneWidget);
        expect(find.byKey(const Key('end-session')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(rig.controller.endEarly);
      });
    }
  });

  group('summary', () {
    Future<SessionFlowController> summaryController(
      WidgetTester tester, {
      bool synthetic = false,
    }) async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.repo.syntheticSummary = synthetic;
      await tester.runAsync(() async {
        await rig.toCameraCheck();
        await rig.controller.endEarly();
      });
      return rig.controller;
    }

    testWidgets('shows coverage, face share and Not evaluable with its reason',
        (tester) async {
      useWindow(tester, 800, 900);
      final c = await summaryController(tester);
      await pumpFlow(tester, c);

      expect(find.text('Session summary'), findsOneWidget);
      expect(find.byKey(const Key('coverage-total')), findsOneWidget);
      expect(find.text('30.0 s'), findsOneWidget);
      expect(find.text('21.0 s (70 %)'), findsOneWidget);
      expect(find.text('6.0 s'), findsOneWidget);
      expect(find.text('3.0 s'), findsOneWidget);
      expect(find.text('72 %'), findsOneWidget);
      expect(find.text('Not evaluable'), findsOneWidget);
      expect(find.text('Regional validation did not pass.'), findsOneWidget);
      expect(find.byKey(const Key('synthetic-note')), findsNothing);
      expect(find.text('Back to home'), findsOneWidget);
    });

    testWidgets('a development estimator gets the no-claims note',
        (tester) async {
      useWindow(tester, 800, 900);
      final c = await summaryController(tester, synthetic: true);
      await pumpFlow(tester, c);
      expect(find.text('Development estimator — no measurement claims'),
          findsOneWidget);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('summary has no overflow at ${width.toInt()} px',
          (tester) async {
        useWindow(tester, width, width == 360 ? 640 : 900);
        final c = await summaryController(tester, synthetic: true);
        await pumpFlow(tester, c);
        expect(find.text('Not evaluable'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Back to home leaves the flow', (tester) async {
      useWindow(tester, 800, 900);
      final c = await summaryController(tester);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-flow'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SessionFlowScreen(controller: c),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open-flow')));
      await tester.pumpAndSettle();
      expect(find.text('Session summary'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary-home')));
      await tester.pumpAndSettle();
      expect(find.text('Session summary'), findsNothing);
      expect(find.byKey(const Key('open-flow')), findsOneWidget);
    });
  });

  group('layout at phone, tablet and desktop widths', () {
    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('flow panels have no overflow at ${width.toInt()} px',
          (tester) async {
        useWindow(tester, width, width == 360 ? 700 : 900);
        final rig = Rig();
        addTearDown(rig.dispose);
        rig.repo.validationResult = failedValidation;

        await drive(tester, rig.controller.loadIntro);
        await pumpFlow(tester, rig.controller);
        expect(tester.takeException(), isNull, reason: 'intro');

        await drive(tester, rig.controller.begin);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'camera check');

        await drive(tester, () async {
          await rig.controller.runCameraCheck();
          rig.controller.continueToCalibration();
        });
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'calibration intro');

        await drive(tester, () async {
          await rig.controller.startCalibration();
        });
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'calibration result');

        await drive(tester, () async {
          rig.controller.continueToValidation();
          await rig.controller.startValidation();
        });
        await tester.pump();
        expect(find.text('Validation not passed'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'validation result');
      });
    }
  });
}

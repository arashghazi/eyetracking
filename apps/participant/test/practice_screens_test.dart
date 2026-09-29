import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/app_scope.dart';
import 'package:participant_app/features/assignments/application/topic_controller.dart';
import 'package:participant_app/features/assignments/presentation/topic_screen.dart';
import 'package:participant_app/features/session/application/gradual_practice_controller.dart';
import 'package:participant_app/features/session/application/interest_practice_controller.dart';
import 'package:participant_app/features/session/application/session_flow_controller.dart';
import 'package:participant_app/features/session/domain/session_step.dart';
import 'package:participant_app/features/session/presentation/session_flow_screen.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'practice_kit.dart';
import 'session_kit.dart';

/// Timing for widget tests: protocol seconds stay real seconds, so a number
/// waits 100 s for an answer unless the test answers it.
const widgetTiming = SessionTiming(
  countdownStep: Duration(milliseconds: 2),
  settle: Duration(milliseconds: 8),
  calibrationCapture: Duration(milliseconds: 40),
  validationCapture: Duration(milliseconds: 40),
  progressTick: Duration(milliseconds: 10),
  leadIn: Duration(milliseconds: 2),
  interTrial: Duration(milliseconds: 2),
);

ProtocolDefinition widgetGradual({
  StageResponseMode mode = StageResponseMode.number,
  NumberZone zone = NumberZone.outside,
  int trials = 3,
  int faceLevel = 2,
}) =>
    gradualProtocol(
      baselineSeconds: 0.3,
      postSeconds: 60,
      stages: [
        GradualStage(
          faceLevel: faceLevel,
          numberZone: zone,
          trials: trials,
          trialSeconds: 100,
          responseMode: mode,
        ),
      ],
    );

/// Pumps the flow screen with the app scope the video stage needs.
Future<void> pumpPractice(
  WidgetTester tester,
  SessionFlowController controller, {
  TestBed? bed,
}) async {
  final deps = (bed ?? TestBed()).dependencies;
  await tester.pumpWidget(AppScope(
    dependencies: deps,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: SessionFlowScreen(controller: controller),
    ),
  ));
  await tester.pump();
}

/// A gradual session with the first number of stage 0 on the screen.
Future<Rig> gradualAtTrial(
  WidgetTester tester, {
  required double width,
  required double height,
  ProtocolDefinition? protocol,
  Profile profile =
      const Profile(displayName: 'Sam', responseMode: ResponseMode.keyboard),
}) async {
  final rig = protocolRig(
    protocol ?? widgetGradual(),
    profile: profile,
    timing: widgetTiming,
    screen: ScreenInfo(w: width, h: height),
  );
  addTearDown(rig.dispose);
  await tester.runAsync(() async {
    await rig.toPractice();
    rig.frames.autoFrames = false;
    await rig.controller.startPractice();
    await until(() => rig.controller.gradual!.phase == GradualPhase.trial,
        what: 'the first number');
  });
  await pumpPractice(tester, rig.controller);
  return rig;
}

/// Lets real timers run (the pause between two numbers).
Future<void> real(WidgetTester tester, Future<void> Function() work) async {
  await tester.runAsync(work);
  await tester.pump();
}

void main() {
  group('home: your next session', () {
    Assignment assignment(
      String id,
      String status, {
      int order = 0,
      String name = 'Practice',
      ProtocolPath path = ProtocolPath.gradualFace,
      String? topic,
      String? title,
    }) =>
        Assignment(
          id: id,
          orderIndex: order,
          status: status,
          protocol: ProtocolRef(id: '1', name: name, path: path),
          topic: topic,
          contentTitle: title,
        );

    testWidgets('lists the assignments in order with what to do next',
        (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [
          assignment('3', AssignmentStatus.completed, order: 2, name: 'Warm-up'),
          assignment('1', AssignmentStatus.pendingTopic,
              order: 0,
              name: 'Conversation',
              path: ProtocolPath.interestConversation),
          assignment('2', AssignmentStatus.contentPending,
              order: 1,
              name: 'Second conversation',
              path: ProtocolPath.interestConversation,
              topic: 'trains'),
          assignment('4', AssignmentStatus.ready, order: 3, name: 'Numbers'),
          assignment('5', AssignmentStatus.inProgress, order: 4, name: 'Numbers 2'),
          assignment('6', AssignmentStatus.cancelled, order: 5, name: 'Old one'),
        ]),
      );
      await pumpApp(tester, bed);

      expect(find.text('Your next session'), findsOneWidget);
      // pending_topic: a button to confirm the topic.
      expect(find.byKey(const Key('confirm-topic-1')), findsOneWidget);
      expect(find.text('Confirm my topic'), findsOneWidget);
      // content_pending: a sentence and no button.
      expect(find.byKey(const Key('content-pending-2')), findsOneWidget);
      expect(find.text('Content being prepared by your researcher'), findsOneWidget);
      expect(find.byKey(const Key('confirm-topic-2')), findsNothing);
      expect(find.byKey(const Key('prepare-2')), findsNothing);
      // ready and in_progress: Prepare for session.
      expect(find.byKey(const Key('prepare-4')), findsOneWidget);
      expect(find.byKey(const Key('prepare-5')), findsOneWidget);
      expect(find.text('Prepare for session'), findsNWidgets(2));
      // completed: a done mark; cancelled ones are not listed.
      expect(find.byKey(const Key('done-3')), findsOneWidget);
      expect(find.text('Old one'), findsNothing);

      // In the server's order.
      double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      expect(top('assignment-1'), lessThan(top('assignment-2')));
      expect(top('assignment-2'), lessThan(top('assignment-3')));
      expect(top('assignment-3'), lessThan(top('assignment-4')));
      expect(top('assignment-4'), lessThan(top('assignment-5')));

      // The free measurement-only session comes below, with its own label.
      final free = find.byKey(const Key('start-session'));
      await tester.ensureVisible(free);
      expect(find.text('Camera and calibration check only'), findsOneWidget);
      expect(tester.getTopLeft(free).dy,
          greaterThan(tester.getTopLeft(find.byKey(const Key('assignment-5'))).dy));
    });

    testWidgets('Prepare for session opens the introduction of that assignment',
        (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(
          items: [assignment('4', AssignmentStatus.ready, name: 'Numbers')],
        ),
      );
      await pumpApp(tester, bed);
      await tester.tap(find.byKey(const Key('prepare-4')));
      await tester.pumpAndSettle();
      expect(find.text('Prepare for session'), findsWidgets);
      expect(find.text('Practice'), findsWidgets, reason: 'the intro lists the practice step');
      expect(find.byKey(const Key('stop-sentence')), findsOneWidget);
    });

    testWidgets('an empty list says nothing has been assigned', (tester) async {
      useWindow(tester, 800, 1400);
      await pumpApp(tester, TestBed());
      expect(find.byKey(const Key('no-assignments')), findsOneWidget);
    });

    testWidgets('a participant who is not ready cannot prepare yet',
        (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed(
        home: FakeHomeRepository(reasons: const [ReadinessReason.demographicsIncomplete]),
        assignments: FakeAssignmentsRepository(
          items: [assignment('4', AssignmentStatus.ready)],
        ),
      );
      await pumpApp(tester, bed);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('prepare-4'))).onPressed,
        isNull,
      );
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the assignments card fits ${width.toInt()} px',
          (tester) async {
        useWindow(tester, width, 900);
        final bed = TestBed(
          assignments: FakeAssignmentsRepository(items: [
            assignment('1', AssignmentStatus.pendingTopic,
                name: 'A rather long protocol name for a conversation'),
            assignment('2', AssignmentStatus.contentPending, order: 1),
            assignment('3', AssignmentStatus.ready, order: 2),
            assignment('4', AssignmentStatus.completed, order: 3),
          ]),
        );
        await pumpApp(tester, bed);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('confirm my topic', () {
    Assignment pending() => const Assignment(
          id: '1',
          status: AssignmentStatus.pendingTopic,
          protocol: ProtocolRef(
            id: '1',
            name: 'Conversation',
            path: ProtocolPath.interestConversation,
          ),
        );

    testWidgets('an interest chip, free text, submit, then the content-pending state',
        (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [pending()]),
        profile: FakeProfileRepository()
          ..profile = const Profile(interests: ['trains', 'space']),
      );
      await pumpApp(tester, bed);
      await tester.tap(find.byKey(const Key('confirm-topic-1')));
      await tester.pumpAndSettle();

      expect(find.text('Confirm my topic'), findsWidgets);
      expect(find.byKey(const Key('interest-trains')), findsOneWidget);
      expect(find.byKey(const Key('interest-space')), findsOneWidget);
      expect(find.text('Anything you would like the conversation to include?'),
          findsOneWidget);
      // Nothing to send yet.
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('topic-submit'))).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('interest-space')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('topic-field'))).controller!.text,
          'space');
      await tester.enterText(find.byKey(const Key('free-text-field')), 'rockets please');
      await tester.pump();
      await tester.tap(find.byKey(const Key('topic-submit')));
      await tester.pumpAndSettle();

      expect(bed.assignments.submitted.single.topic, 'space');
      expect(bed.assignments.submitted.single.freeText, 'rockets please');
      expect(find.byKey(const Key('topic-submitted')), findsOneWidget);
      expect(find.text('Content being prepared by your researcher'), findsWidgets);

      // Back home the assignment now waits for content: no button.
      await tester.tap(find.byKey(const Key('topic-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-topic-1')), findsNothing);
      expect(find.byKey(const Key('content-pending-1')), findsOneWidget);
    });

    testWidgets('a typed topic works without interests', (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [pending()]),
      );
      await tester.pumpWidget(AppScope(
        dependencies: bed.dependencies,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TopicScreen(assignment: pending()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('interest-chips')), findsNothing);

      await tester.enterText(find.byKey(const Key('topic-field')), '  volcanoes ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('topic-submit')));
      await tester.pumpAndSettle();
      expect(bed.assignments.submitted.single.topic, 'volcanoes');
      expect(bed.assignments.submitted.single.freeText, isNull);
    });

    testWidgets('a server refusal is shown and the form stays', (tester) async {
      useWindow(tester, 800, 1000);
      final repo = FakeAssignmentsRepository(items: [pending()])
        ..submitFailure = const ApiException('Topic too long.', statusCode: 422);
      final bed = TestBed(assignments: repo);
      final controller = TopicController(
        assignments: repo,
        profile: bed.profile,
        assignment: pending(),
      );
      await tester.pumpWidget(AppScope(
        dependencies: bed.dependencies,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TopicScreen(assignment: pending(), controller: controller),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('topic-field')), 'x');
      await tester.pump();
      await tester.tap(find.byKey(const Key('topic-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Topic too long.'), findsOneWidget);
      expect(find.byKey(const Key('topic-submitted')), findsNothing);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the topic screen fits ${width.toInt()} px', (tester) async {
        useWindow(tester, width, 640);
        final bed = TestBed(
          assignments: FakeAssignmentsRepository(items: [pending()]),
          profile: FakeProfileRepository()
            ..profile = const Profile(
                interests: ['trains', 'space', 'football', 'painting', 'chess']),
        );
        await tester.pumpWidget(AppScope(
          dependencies: bed.dependencies,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: TopicScreen(assignment: pending()),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('gradual practice stage', () {
    for (final size in [(360.0, 640.0), (800.0, 900.0), (1440.0, 900.0)]) {
      testWidgets('shows face, number and answer controls at ${size.$1.toInt()} px',
          (tester) async {
        useWindow(tester, size.$1, size.$2);
        final rig = await gradualAtTrial(tester, width: size.$1, height: size.$2);
        final g = rig.controller.gradual!;

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('practice-stage')), findsOneWidget);
        expect(find.byKey(const Key('face-stimulus')), findsOneWidget);
        expect(find.byKey(const Key('trial-number')), findsOneWidget);
        expect(find.byKey(const Key('answer-field')), findsOneWidget);
        expect(find.byKey(const Key('answer-submit')), findsOneWidget);
        // Pause and End stay visible.
        expect(find.byKey(const Key('pause')), findsOneWidget);
        expect(find.byKey(const Key('end-session')), findsOneWidget);
        // The number is drawn exactly where the trial says.
        final rect = g.stimulus!.placement.rect;
        final topLeft = tester.getTopLeft(find.byKey(const Key('trial-number')));
        expect(topLeft.dx, closeTo(rect.x, 0.5));
        expect(topLeft.dy, closeTo(rect.y, 0.5));
        expect(find.text(g.stimulus!.shown), findsOneWidget);
        // No score, no verdict on the screen.
        expect(find.textContaining('%'), findsNothing);
        expect(find.textContaining('score', findRichText: true), findsNothing);
        expect(find.textContaining('wrong'), findsNothing);
        // The answer controls sit below the face card.
        final face = g.layout.faceBox;
        expect(tester.getTopLeft(find.byKey(const Key('answer-field'))).dy,
            greaterThan(face.bottom - 1));
      });
    }

    testWidgets('typing the number and pressing Enter answers it', (tester) async {
      useWindow(tester, 800, 900);
      final rig = await gradualAtTrial(tester, width: 800, height: 900);
      final g = rig.controller.gradual!;
      final shown = g.stimulus!.shown;

      await tester.enterText(find.byKey(const Key('answer-field')), shown);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await real(tester, () => until(() => g.trialNumber == 2, what: 'the next number'));

      expect(g.trialNumber, 2);
      await tester.pump();
      expect(find.byKey(const Key('practice-caption')), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      // The field is fresh for the new number.
      expect(
        tester.widget<TextField>(find.byKey(const Key('answer-field'))).controller!.text,
        isEmpty,
      );
    });

    testWidgets('only digits are accepted, at most two', (tester) async {
      useWindow(tester, 800, 900);
      await gradualAtTrial(tester, width: 800, height: 900);
      await tester.enterText(find.byKey(const Key('answer-field')), 'a1b2c3');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const Key('answer-field'))).controller!.text,
        '12',
      );
    });

    testWidgets('on a touch profile the on-screen digit pad answers', (tester) async {
      useWindow(tester, 360, 640);
      final rig = await gradualAtTrial(
        tester,
        width: 360,
        height: 640,
        profile: const Profile(responseMode: ResponseMode.touch),
      );
      final g = rig.controller.gradual!;
      expect(find.byKey(const Key('answer-field')), findsNothing);
      expect(find.byKey(const Key('pad-5')), findsOneWidget);
      // Answer is disabled until a digit is entered.
      expect(tester.widget<FilledButton>(find.byKey(const Key('answer-submit'))).onPressed,
          isNull);

      final shown = g.stimulus!.shown;
      for (final digit in shown.split('')) {
        await tester.tap(find.byKey(Key('pad-$digit')));
        await tester.pump();
      }
      expect(tester.widget<Text>(find.byKey(const Key('pad-display'))).data, shown);
      // Backspace and re-type.
      await tester.tap(find.byKey(const Key('pad-back')));
      await tester.pump();
      await tester.tap(find.byKey(Key('pad-${shown[shown.length - 1]}')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('answer-submit')));
      await real(tester, () => until(() => g.trialNumber == 2, what: 'the next number'));
      expect(g.trialNumber, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('four-choice buttons answer; the shown number is one of them',
        (tester) async {
      useWindow(tester, 360, 640);
      final rig = await gradualAtTrial(
        tester,
        width: 360,
        height: 640,
        protocol: widgetGradual(mode: StageResponseMode.fourChoice),
      );
      final g = rig.controller.gradual!;
      final shown = g.stimulus!.shown;
      for (final option in g.stimulus!.options) {
        expect(find.byKey(Key('choice-$option')), findsOneWidget);
      }
      expect(find.byKey(Key('choice-$shown')), findsOneWidget);
      await tester.tap(find.byKey(Key('choice-$shown')));
      await real(tester, () => until(() => g.trialNumber == 2, what: 'the next number'));
      expect(g.trialNumber, 2);
    });

    testWidgets('symbol mode shows a picture symbol and four symbol buttons',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = await gradualAtTrial(
        tester,
        width: 800,
        height: 900,
        protocol: widgetGradual(mode: StageResponseMode.symbol),
      );
      final g = rig.controller.gradual!;
      expect(find.byKey(const Key('trial-number')), findsOneWidget);
      for (final name in ['circle', 'square', 'triangle', 'star']) {
        expect(find.byKey(Key('choice-$name')), findsOneWidget);
      }
      // The shown symbol is a picture, not text.
      expect(find.text(g.stimulus!.shown), findsNothing);
      await tester.tap(find.byKey(Key('choice-${g.stimulus!.shown}')));
      await real(tester, () => until(() => g.trialNumber == 2, what: 'the next number'));
      expect(g.trialNumber, 2);
    });

    for (final level in [0, 1, 2, 3]) {
      testWidgets('face level $level draws without overflow', (tester) async {
        useWindow(tester, 800, 900);
        await gradualAtTrial(
          tester,
          width: 800,
          height: 900,
          protocol: widgetGradual(faceLevel: level, zone: NumberZone.eyeRegion),
        );
        expect(find.byKey(const Key('face-stimulus')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('after the trials the comfort question shows the protocol scale '
        'as large buttons, then the decision', (tester) async {
      useWindow(tester, 360, 640);
      final rig = await gradualAtTrial(tester, width: 360, height: 640);
      final g = rig.controller.gradual!;
      rig.repo.scriptedDecisions.add(const StageDecision(
        kind: StageDecisionKind.hold,
        nextStageIndex: 0,
        reason: 'accuracy',
      ));
      await real(tester, () async {
        for (var n = 0; n < 3; n++) {
          await until(() => g.phase == GradualPhase.trial && g.trialNumber == n + 1,
              what: 'trial ${n + 1}');
          g.submit(g.stimulus!.shown);
        }
        await until(() => g.phase == GradualPhase.comfort, what: 'the comfort question');
      });

      expect(find.byKey(const Key('comfort-question')), findsOneWidget);
      for (final label in kDefaultComfortLabels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byKey(const Key('face-stimulus')), findsNothing,
          reason: 'the question sits on a plain background');
      expect(find.byKey(const Key('pause')), findsOneWidget);
      expect(find.byKey(const Key('end-session')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Each answer is a real button, at least 48 px tall.
      expect(tester.getSize(find.byKey(const Key('comfort-4'))).height,
          greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(const Key('comfort-4')));
      await real(tester, () => until(() => g.phase == GradualPhase.decision, what: 'decision'));
      expect(find.text("Let's do this one again."), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(rig.repo.stageRequests.single.comfort, 4);

      await tester.tap(find.byKey(const Key('decision-continue')));
      // The timers of the new stage run on the test clock.
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));
      expect(g.phase, GradualPhase.trial);
      expect(g.stageIndex, 0);
      expect(find.byKey(const Key('trial-number')), findsOneWidget);
      // The number's timeout runs on the test clock: stop it.
      g.cancel();
    });

    testWidgets('a failed upload shows the message with a retry', (tester) async {
      useWindow(tester, 800, 900);
      final rig = await gradualAtTrial(tester, width: 800, height: 900);
      final g = rig.controller.gradual!;
      rig.repo.trialsFailure = const ApiException('Server busy.', statusCode: 503);
      await real(tester, () async {
        for (var n = 0; n < 3; n++) {
          await until(() => g.phase == GradualPhase.trial && g.trialNumber == n + 1,
              what: 'trial ${n + 1}');
          g.submit(g.stimulus!.shown);
        }
        await until(() => g.phase == GradualPhase.problem, what: 'the problem');
      });
      expect(find.text('Server busy.'), findsOneWidget);
      rig.repo.trialsFailure = null;
      await tester.tap(find.byKey(const Key('practice-retry')));
      await real(tester, () => until(() => g.phase == GradualPhase.comfort, what: 'comfort'));
      expect(find.byKey(const Key('comfort-question')), findsOneWidget);
    });

    testWidgets('the step list names the practice steps', (tester) async {
      useWindow(tester, 1440, 900);
      final rig = await gradualAtTrial(tester, width: 1440, height: 900);
      expect(rig.controller.step, SessionStep.practice);
      for (final label in [
        'Camera check',
        'Calibration',
        'Validation',
        'Baseline',
        'Practice',
        'Post observation',
        'Comfort & summary',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('pausing shows the paused panel; resuming brings a new number',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = await gradualAtTrial(tester, width: 800, height: 900);
      await real(tester, rig.controller.pause);
      expect(find.byKey(const Key('paused-panel')), findsOneWidget);
      expect(find.byKey(const Key('trial-number')), findsNothing);
      await real(tester, rig.controller.resume);
      await real(tester, () => until(
            () => rig.controller.gradual!.phase == GradualPhase.trial,
            what: 'a number again',
          ));
      expect(find.byKey(const Key('trial-number')), findsOneWidget);
      // Leave nothing running.
      await tester.runAsync(rig.controller.endEarly);
    });
  });

  group('practice instructions', () {
    testWidgets('the practice and post panels explain what to do', (tester) async {
      useWindow(tester, 800, 900);
      final rig = protocolRig(widgetGradual(), timing: widgetTiming,
          screen: const ScreenInfo(w: 800, h: 900));
      addTearDown(rig.dispose);
      await tester.runAsync(rig.toPractice);
      await pumpPractice(tester, rig.controller);

      expect(find.text('Practice'), findsWidgets);
      expect(find.byKey(const Key('practice-start')), findsOneWidget);
      expect(find.textContaining('there is no score'), findsOneWidget);
      expect(find.text('Start practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('interest practice', () {
    Future<(Rig, InterestPracticeController, TestBed)> interestRunning(
      WidgetTester tester, {
      required double width,
      required double height,
      Profile profile = const Profile(displayName: 'Sam'),
      VideoStageBuilder? video,
    }) async {
      final bed = TestBed(
        videoStage: video ?? FakeVideoStage.builder(duration: const Duration(seconds: 30)),
      );
      final rig = protocolRig(
        interestProtocol(baselineSeconds: 0.3, postSeconds: 60),
        content: sampleContent(),
        profile: profile,
        timing: widgetTiming,
        screen: ScreenInfo(w: width, h: height),
      );
      addTearDown(rig.dispose);
      rig.repo.answerResult = (a) => a.kind == AnswerKind.interaction
          ? const AnswerResult(nextSegmentId: 's2')
          : const AnswerResult(correct: true);
      await tester.runAsync(() async {
        await rig.toPractice();
        rig.frames.autoFrames = false;
        await rig.controller.startPractice();
      });
      await pumpPractice(tester, rig.controller, bed: bed);
      return (rig, rig.controller.interest!, bed);
    }

    for (final size in [(360.0, 640.0), (800.0, 900.0), (1440.0, 900.0)]) {
      testWidgets('video, question and comprehension fit ${size.$1.toInt()} px',
          (tester) async {
        useWindow(tester, size.$1, size.$2);
        final (rig, i, _) =
            await interestRunning(tester, width: size.$1, height: size.$2);

        expect(find.byKey(const Key('fake-video')), findsOneWidget);
        expect(find.text('/media/s1'), findsOneWidget);
        expect(find.byKey(const Key('pause')), findsOneWidget);
        expect(find.byKey(const Key('end-session')), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The player reported a rectangle: the layout follows it.
        await tester.pump();
        expect(i.videoRect, isNotNull);
        // The 16:9 picture sits centred in the player below the control bar.
        final expected = containedVideoRect(
          Box(0, kControlBarHeightForTest, size.$1, size.$2 - kControlBarHeightForTest),
          1920,
          1080,
        );
        expect(i.videoRect!.x, closeTo(expected.x, 0.5));
        expect(i.videoRect!.y, closeTo(expected.y, 0.5));
        expect(i.videoRect!.w, closeTo(expected.w, 0.5));
        expect(i.videoRect!.h, closeTo(expected.h, 0.5));

        await real(tester, () async {
          i.onVideoPlaying();
          await i.onVideoEnded();
        });
        expect(find.byKey(const Key('interaction-question')), findsOneWidget);
        expect(find.text('Which do you prefer?'), findsOneWidget);
        expect(find.byKey(const Key('option-0')), findsOneWidget);
        expect(find.byKey(const Key('option-1')), findsOneWidget);
        expect(find.byKey(const Key('fake-video')), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('option-0')));
        await real(tester, () => until(() => i.phase == InterestPhase.playing, what: 'next video'));
        expect(find.text('/media/s2'), findsOneWidget);

        await real(tester, () async {
          i.onVideoPlaying();
          await i.onVideoEnded();
        });
        expect(find.byKey(const Key('comprehension-question')), findsOneWidget);
        expect(find.text('Question 1 of 2'), findsOneWidget);
        expect(find.text('What colour was the train?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('option-0')));
        await tester.pump();
        await tester.pump();
        expect(find.text('Question 2 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a video that cannot load says so and offers a retry',
        (tester) async {
      useWindow(tester, 800, 900);
      final (rig, i, _) = await interestRunning(
        tester,
        width: 800,
        height: 900,
        video: FakeVideoStage.builder(
          duration: const Duration(seconds: 30),
          failUrls: {'/media/s1'},
          failOnce: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('The video is not ready'), findsOneWidget);
      expect(find.byKey(const Key('video-retry')), findsOneWidget);
      expect(i.videoUrl, isNull);

      await tester.tap(find.byKey(const Key('video-retry')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('The video is not ready'), findsNothing);
      expect(find.byKey(const Key('fake-video')), findsOneWidget);
      expect(rig.controller.error, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('captions appear under the video only when the profile asks',
        (tester) async {
      useWindow(tester, 800, 900);
      await interestRunning(
        tester,
        width: 800,
        height: 900,
        profile: const Profile(accessibilityNeeds: ['captions']),
      );
      expect(find.byKey(const Key('video-caption')), findsOneWidget);
      expect(find.text('Hi Sam, today we talk about trains.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no captions without the setting', (tester) async {
      useWindow(tester, 800, 900);
      await interestRunning(tester, width: 800, height: 900);
      expect(find.byKey(const Key('video-caption')), findsNothing);
      expect(find.text('Hi Sam, today we talk about trains.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('summary with outcomes', () {
    Future<SessionFlowController> summaryFor(
      WidgetTester tester, {
      required SessionOutcomes outcomes,
      ProtocolPath path = ProtocolPath.gradualFace,
      bool synthetic = false,
    }) async {
      final protocol =
          path == ProtocolPath.gradualFace ? widgetGradual() : interestProtocol();
      final rig = protocolRig(protocol, timing: widgetTiming);
      addTearDown(rig.dispose);
      rig.repo.syntheticSummary = synthetic;
      rig.repo.outcomes = outcomes;
      rig.repo.stageRecords = const [
        StageRecord(stageIndex: 0, decision: 'advance', trials: 6),
      ];
      await tester.runAsync(() async {
        await rig.toCameraCheck();
        await rig.controller.endEarly();
      });
      return rig.controller;
    }

    const undecided = SessionOutcomes(
      gaze: GazeOutcome(reason: 'synthetic_estimator'),
      numberTask: NumberTaskOutcome(trials: 12, correct: 10, share: 0.83, stagesCompleted: 2),
      comfort: ComfortOutcome(answers: 3, min: 3, mean: 3.7, lowCount: 0),
      improvement: ImprovementOutcome(reason: 'synthetic_estimator'),
    );

    testWidgets('"Cannot be judged yet" with the reason when gaze is not evaluable',
        (tester) async {
      useWindow(tester, 800, 1400);
      final c = await summaryFor(tester, outcomes: undecided, synthetic: true);
      await pumpPractice(tester, c);

      expect(find.byKey(const Key('outcome-improvement')), findsOneWidget);
      expect(find.text('Cannot be judged yet'), findsOneWidget);
      expect(find.byKey(const Key('improvement-reason')), findsOneWidget);
      expect(find.text('The development estimator makes no measurement claims.'),
          findsNWidgets(2), reason: 'gaze card and improvement line');
      // Gaze: not evaluable, no shares.
      expect(find.byKey(const Key('gaze-status')), findsOneWidget);
      expect(find.text('Not evaluable'), findsWidgets);
      expect(find.byKey(const Key('gaze-baseline')), findsNothing);
      // The development banner stays.
      expect(find.byKey(const Key('synthetic-note')), findsOneWidget);
      expect(find.text('Development estimator — no measurement claims'), findsOneWidget);
    });

    testWidgets('gaze, number task and comfort side by side on a wide screen',
        (tester) async {
      useWindow(tester, 1440, 1000);
      final c = await summaryFor(tester, outcomes: undecided);
      await pumpPractice(tester, c);

      final gaze = tester.getTopLeft(find.byKey(const Key('outcome-gaze')));
      final task = tester.getTopLeft(find.byKey(const Key('outcome-number-task')));
      final comfort = tester.getTopLeft(find.byKey(const Key('outcome-comfort')));
      expect(task.dy, gaze.dy);
      expect(comfort.dy, gaze.dy);
      expect(task.dx, greaterThan(gaze.dx));
      expect(comfort.dx, greaterThan(task.dx));
      expect(find.byKey(const Key('outcome-comprehension')), findsNothing);
      expect(find.text('10 (83 %)'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.byKey(const Key('comfort-min')), findsOneWidget);
      expect(find.text('3.7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cards stack on a phone', (tester) async {
      useWindow(tester, 360, 900);
      final c = await summaryFor(tester, outcomes: undecided);
      await pumpPractice(tester, c);

      final gaze = tester.getTopLeft(find.byKey(const Key('outcome-gaze')));
      final task = tester.getTopLeft(find.byKey(const Key('outcome-number-task')));
      final comfort = tester.getTopLeft(find.byKey(const Key('outcome-comfort')));
      expect(task.dx, gaze.dx);
      expect(task.dy, greaterThan(gaze.dy));
      expect(comfort.dy, greaterThan(task.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the interest path shows comprehension instead of the number task',
        (tester) async {
      useWindow(tester, 800, 1400);
      final c = await summaryFor(
        tester,
        path: ProtocolPath.interestConversation,
        outcomes: const SessionOutcomes(
          comprehension: ComprehensionOutcome(answered: 3, correct: 2, share: 0.67),
          comfort: ComfortOutcome(answers: 2, min: 4, mean: 4.5, lowCount: 0),
        ),
      );
      await pumpPractice(tester, c);
      expect(find.byKey(const Key('outcome-comprehension')), findsOneWidget);
      expect(find.byKey(const Key('outcome-number-task')), findsNothing);
      expect(find.text('2 (67 %)'), findsOneWidget);
    });

    testWidgets('evaluable gaze shows both shares; all three criteria met',
        (tester) async {
      useWindow(tester, 800, 1400);
      final c = await summaryFor(
        tester,
        outcomes: const SessionOutcomes(
          gaze: GazeOutcome(baselineEyeShare: 0.2, postEyeShare: 0.4, evaluable: true),
          numberTask: NumberTaskOutcome(trials: 6, correct: 6, share: 1, stagesCompleted: 1),
          comfort: ComfortOutcome(answers: 2, min: 4, mean: 4.5),
          improvement: ImprovementOutcome(
            eligible: true,
            result: true,
            eyeShareUp: true,
            comfortNotWorse: true,
            comprehensionMaintained: true,
          ),
        ),
      );
      await pumpPractice(tester, c);
      expect(find.text('20 %'), findsOneWidget);
      expect(find.text('40 %'), findsOneWidget);
      expect(find.text('All three criteria met'), findsOneWidget);
      expect(find.text('Eye share went up'), findsOneWidget);
    });

    testWidgets('"Not met" when a criterion fails', (tester) async {
      useWindow(tester, 800, 1400);
      final c = await summaryFor(
        tester,
        outcomes: const SessionOutcomes(
          gaze: GazeOutcome(baselineEyeShare: 0.4, postEyeShare: 0.2, evaluable: true),
          improvement: ImprovementOutcome(
            eligible: true,
            result: false,
            eyeShareUp: false,
            comfortNotWorse: true,
            comprehensionMaintained: true,
          ),
        ),
      );
      await pumpPractice(tester, c);
      expect(find.text('Not met'), findsOneWidget);
      expect(find.text('Cannot be judged yet'), findsNothing);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the summary with outcomes fits ${width.toInt()} px', (tester) async {
        useWindow(tester, width, width == 360 ? 640 : 900);
        final c = await summaryFor(tester, outcomes: undecided, synthetic: true);
        await pumpPractice(tester, c);
        expect(find.text('Cannot be judged yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the final comfort question', () {
    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('is asked with the protocol scale after the post observation, '
          'at ${width.toInt()} px', (tester) async {
        final height = width == 360 ? 640.0 : 900.0;
        useWindow(tester, width, height);
        final protocol = gradualProtocol(
          baselineSeconds: 0.3,
          postSeconds: 0.3,
          stages: const [GradualStage(trials: 1, trialSeconds: 100)],
        );
        final rig = protocolRig(
          protocol,
          timing: widgetTiming,
          screen: ScreenInfo(w: width, h: height),
        );
        addTearDown(rig.dispose);
        rig.repo.scriptedDecisions.add(const StageDecision(
          kind: StageDecisionKind.complete,
          reason: 'all_stages_done',
        ));
        await tester.runAsync(() async {
          await rig.toPractice();
          await rig.controller.startPractice();
          final g = rig.controller.gradual!;
          await until(() => g.phase == GradualPhase.trial, what: 'a number');
          g.submit(g.stimulus!.shown);
          await until(() => g.phase == GradualPhase.comfort, what: 'stage comfort');
          await g.answerComfort(4);
          await g.continueAfterDecision();
          await rig.controller.startPost();
          await until(() => rig.controller.askingComfort, what: 'final comfort');
        });
        await pumpPractice(tester, rig.controller);

        expect(find.text('Almost done'), findsOneWidget);
        expect(find.byKey(const Key('comfort-question')), findsOneWidget);
        expect(find.text('How did the session feel?'), findsOneWidget);
        for (final label in kDefaultComfortLabels) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('Comfort & summary'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.byKey(const Key('comfort-5')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('comfort-5')));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(rig.controller.step, SessionStep.summary);
        expect(rig.controller.askingComfort, isFalse);
        final answers = rig.repo.events
            .where((e) => e.type == SessionEventType.comfortAnswer)
            .toList();
        expect(answers.last.payload, {'value': 5, 'segment': 'post'});
        expect(find.text('Session summary'), findsOneWidget);
      });
    }

    testWidgets('can be skipped', (tester) async {
      useWindow(tester, 800, 900);
      final protocol = gradualProtocol(
        baselineSeconds: 0.3,
        postSeconds: 0.3,
        stages: const [GradualStage(trials: 1, trialSeconds: 100)],
      );
      final rig = protocolRig(
        protocol,
        timing: widgetTiming,
        screen: const ScreenInfo(w: 800, h: 900),
      );
      addTearDown(rig.dispose);
      rig.repo.scriptedDecisions.add(const StageDecision(kind: StageDecisionKind.complete));
      await tester.runAsync(() async {
        await rig.toPractice();
        await rig.controller.startPractice();
        final g = rig.controller.gradual!;
        await until(() => g.phase == GradualPhase.trial, what: 'a number');
        g.submit(g.stimulus!.shown);
        await until(() => g.phase == GradualPhase.comfort, what: 'stage comfort');
        await g.answerComfort(4);
        await g.continueAfterDecision();
        await rig.controller.startPost();
        await until(() => rig.controller.askingComfort, what: 'final comfort');
      });
      await pumpPractice(tester, rig.controller);
      await tester.tap(find.byKey(const Key('comfort-skip')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(rig.controller.step, SessionStep.summary);
      final answers = rig.repo.events
          .where((e) => e.type == SessionEventType.comfortAnswer)
          .toList();
      expect(answers, hasLength(1), reason: 'only the stage answer was sent');
    });
  });
}

const kControlBarHeightForTest = 40.0;

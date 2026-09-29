import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/application/gradual_practice_controller.dart';
import 'package:participant_app/features/session/application/segment_recorder.dart';
import 'package:participant_app/features/session/domain/session_step.dart';

import 'practice_kit.dart';
import 'session_kit.dart';

/// Answers the trials of the running stage until the comfort question shows.
Future<void> answerStage(GradualPracticeController g) async {
  while (true) {
    await until(
      () =>
          g.phase == GradualPhase.trial ||
          g.phase == GradualPhase.comfort ||
          g.phase == GradualPhase.problem,
      what: 'trial or comfort',
    );
    if (g.phase != GradualPhase.trial) return;
    final current = g.stimulus!;
    g.submit(current.shown);
    await until(
      () => g.phase != GradualPhase.trial || !identical(g.stimulus, current),
      what: 'trial to close',
    );
  }
}

const oneStage = [GradualStage(trials: 2, trialSeconds: 50)];

void main() {
  group('gradual path', () {
    test('baseline, practice, post observation, comfort, summary - with the '
        'layout and events the server expects', () async {
      final rig = protocolRig(gradualProtocol(stages: oneStage));
      addTearDown(rig.dispose);
      final c = rig.controller;
      rig.trackSteps();
      rig.repo.scriptedDecisions.add(const StageDecision(
        kind: StageDecisionKind.complete,
        reason: 'all_stages_done',
      ));

      await rig.toPractice();
      expect(c.hasProtocol, isTrue);
      expect(c.protocol!.path, ProtocolPath.gradualFace);
      expect(rig.repo.created.single.toJson()['assignment_id'], 5,
          reason: 'the session names its assignment');
      expect(c.baselineDuration, const Duration(milliseconds: 300),
          reason: 'the baseline follows the protocol');

      await c.startPractice();
      final g = c.gradual!;
      expect(c.phase, StepPhase.running);
      await answerStage(g);
      expect(g.phase, GradualPhase.comfort);
      await g.answerComfort(5);
      await g.continueAfterDecision();
      expect(g.end, PracticeEnd.completed);
      expect(c.step, SessionStep.post);
      expect(c.phase, StepPhase.idle);

      await c.startPost();
      await until(() => c.askingComfort, what: 'the final comfort question');
      await c.answerFinalComfort(4);
      expect(c.step, SessionStep.summary);
      expect(c.isEnded, isTrue);

      expect(rig.steps, [
        SessionStep.intro,
        SessionStep.cameraCheck,
        SessionStep.calibration,
        SessionStep.validation,
        SessionStep.baseline,
        SessionStep.practice,
        SessionStep.post,
        SessionStep.summary,
      ]);

      // Layout calls carry the segment and, for practice, the stage index.
      expect([for (final l in rig.repo.layouts) (l.segment.wire, l.stageIndex)], [
        ('baseline', null),
        ('practice', 0),
        ('post', null),
      ]);
      // One face card for baseline, practice and post: same regions.
      final faces = {for (final l in rig.repo.layouts) l.layout.faceBox};
      expect(faces, hasLength(1));

      final events = [
        for (final e in rig.repo.events)
          if (e.type != SessionEventType.faceLost &&
              e.type != SessionEventType.faceFound)
            '${e.type.wire} ${jsonEncode(e.payload)}',
      ];
      expect(events, [
        'segment_start {"segment":"baseline"}',
        'segment_end {"segment":"baseline"}',
        'segment_start {"segment":"practice","stage_index":0}',
        'segment_end {"segment":"practice"}',
        'comfort_answer {"value":5,"stage_index":0}',
        'segment_start {"segment":"post"}',
        'segment_end {"segment":"post"}',
        'comfort_answer {"value":4,"segment":"post"}',
        'end {"reason":"completed"}',
      ]);
      expect(rig.repo.trialBatches, hasLength(1));
      expect(rig.repo.sampleCount, greaterThan(0));
    });

    test('the post observation shows the face level of the last stage',
        () async {
      final rig = protocolRig(gradualProtocol(stages: const [
        GradualStage(trials: 1, trialSeconds: 50),
        GradualStage(faceLevel: 1, trials: 1, trialSeconds: 50),
      ]));
      addTearDown(rig.dispose);
      final c = rig.controller;
      rig.repo.scriptedDecisions
        ..add(const StageDecision(kind: StageDecisionKind.advance, nextStageIndex: 1))
        ..add(const StageDecision(kind: StageDecisionKind.complete));
      await rig.toPractice();
      expect(c.observationFaceLevel, 2, reason: 'baseline uses the standard face');

      await c.startPractice();
      final g = c.gradual!;
      await answerStage(g);
      await g.answerComfort(4);
      await g.continueAfterDecision();
      await answerStage(g);
      await g.answerComfort(4);
      await g.continueAfterDecision();
      expect(c.step, SessionStep.post);
      expect(c.observationFaceLevel, 1);
      expect(c.postDuration, const Duration(milliseconds: 300));
    });

    test('a stop decision ends the session politely as ended early',
        () async {
      final rig = protocolRig(gradualProtocol(stages: oneStage));
      addTearDown(rig.dispose);
      final c = rig.controller;
      rig.repo.scriptedDecisions.add(const StageDecision(
        kind: StageDecisionKind.stop,
        reason: 'low_comfort_twice',
      ));
      await rig.toPractice();
      await c.startPractice();
      final g = c.gradual!;
      await answerStage(g);
      await g.answerComfort(1);
      await g.continueAfterDecision();

      await until(() => c.step == SessionStep.summary && c.summary != null,
          what: 'the summary');
      expect(rig.repo.events.last.payload, {'reason': 'ended_early'});
      expect(c.askingComfort, isFalse, reason: 'no more questions after a stop');
      expect(rig.repo.layouts.map((l) => l.segment.wire), isNot(contains('post')));
    });

    test('pausing during practice sends pause and resume; between segments '
        'the pause is local', () async {
      final rig = protocolRig(gradualProtocol(stages: oneStage));
      addTearDown(rig.dispose);
      final c = rig.controller;
      await rig.toPractice();
      await c.startPractice();
      final g = c.gradual!;
      await until(() => g.phase == GradualPhase.trial, what: 'a trial');

      await c.pause();
      expect(c.phase, StepPhase.paused);
      expect(rig.repo.eventTypes.last, SessionEventType.pause);
      expect(rig.frames.isActive, isFalse, reason: 'the camera closes');

      await c.resume();
      expect(c.phase, StepPhase.running);
      expect(rig.repo.eventTypes.last, SessionEventType.resume);
      await answerStage(g);
      expect(g.phase, GradualPhase.comfort);

      // The comfort question is between segments: nothing to pause on the server.
      final before = rig.repo.events.length;
      await c.pause();
      expect(rig.repo.events.length, before, reason: 'local pause');
      await c.resume();
      expect(rig.repo.events.length, before);
      expect(g.phase, GradualPhase.comfort);
      expect(rig.repo.trialBatches, hasLength(1));
    });

    test('ending early during practice goes to the summary', () async {
      final rig = protocolRig(gradualProtocol(stages: oneStage));
      addTearDown(rig.dispose);
      final c = rig.controller;
      await rig.toPractice();
      await c.startPractice();
      await until(() => c.gradual!.phase == GradualPhase.trial, what: 'a trial');
      await c.endEarly();
      expect(c.step, SessionStep.summary);
      expect(rig.repo.events.last.payload, {'reason': 'ended_early'});
    });

    test('a device change during practice: recalibrate, then carry on at the '
        'practice without repeating the baseline', () async {
      final rig = protocolRig(gradualProtocol(stages: oneStage));
      addTearDown(rig.dispose);
      final c = rig.controller;
      await rig.toPractice();
      await c.startPractice();
      final g = c.gradual!;
      await until(() => g.phase == GradualPhase.trial, what: 'a trial');

      rig.frames.emitEvent(FrameSourceEvent.zoomChanged);
      await settle();
      expect(c.phase, StepPhase.changed);
      await until(() => rig.repo.eventTypes.contains(SessionEventType.zoomChanged),
          what: 'zoom event');

      c.recalibrate();
      await c.startCalibration();
      c.continueToValidation();
      await c.startValidation();
      c.continueToBaseline();
      expect(c.step, SessionStep.practice, reason: 'the baseline is not repeated');
      expect(c.phase, StepPhase.idle);

      await c.startPractice();
      expect(c.gradual, same(g));
      await answerStage(g);
      expect(g.phase, GradualPhase.comfort);
      expect(rig.repo.trialBatches, hasLength(1));
      // Opened twice: before and after the recalibration.
      expect(rig.repo.layouts.where((l) => l.segment == SessionSegmentName.practice),
          hasLength(2));
    });
  });

  group('interest path', () {
    test('practice, post video, comfort and summary', () async {
      final rig = protocolRig(
        interestProtocol(),
        content: sampleContent(),
        profile: const Profile(
          displayName: 'Sam',
          accessibilityNeeds: ['Captions please'],
        ),
      );
      addTearDown(rig.dispose);
      final c = rig.controller;
      rig.repo.answerResult = (a) => a.kind == AnswerKind.interaction
          ? const AnswerResult(nextSegmentId: 's2')
          : const AnswerResult(correct: true);
      await rig.toPractice();
      expect(c.isInterest, isTrue);
      expect(c.showCaptions, isTrue, reason: 'the profile asks for captions');

      await c.startPractice();
      final i = c.interest!;
      expect(c.phase, StepPhase.running);
      expect(c.practiceVisible, isTrue);
      expect(i.caption, isNotNull);

      Future<void> playSegment() async {
        i.onVideoRect(const Box(0, 40, 1440, 810));
        i.onVideoPlaying();
        await until(() => c.frameSource.isActive, what: 'camera');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await i.onVideoEnded();
      }

      await playSegment(); // s1 -> question
      await i.answerInteraction('Trains');
      await playSegment(); // s2 -> comprehension
      await i.answerComprehension('Red');
      await i.answerComprehension('Paris');
      expect(c.step, SessionStep.post);
      expect(c.phase, StepPhase.idle);

      await c.startPost();
      expect(c.practiceVisible, isTrue);
      await playSegment(); // s3, the post segment
      await until(() => c.askingComfort, what: 'comfort');
      await c.answerFinalComfort(5);
      expect(c.step, SessionStep.summary);

      expect([for (final l in rig.repo.layouts) l.segment.wire],
          ['baseline', 'practice', 'practice', 'post']);
      // The practice layout is the mapped video layout, not the face card.
      final practice = rig.repo.layouts[1].layout;
      expect(practice.faceBox, const Box(432, 121, 576, 648));
      expect(rig.repo.sampleCount, greaterThan(0));
      expect(rig.repo.answers.map((a) => a.kind), [
        AnswerKind.interaction,
        AnswerKind.comprehension,
        AnswerKind.comprehension,
      ]);
      final types = rig.repo.events.map((e) => e.type.wire).toList();
      expect(types.last, 'end');
      expect(types.where((t) => t == 'comfort_answer'), hasLength(1));
    });

    test('the content is fetched when the practice starts; a failure keeps '
        'the instructions and shows the message', () async {
      final rig = protocolRig(interestProtocol()); // no content -> 404
      addTearDown(rig.dispose);
      final c = rig.controller;
      await rig.toPractice();
      await c.startPractice();
      expect(c.phase, StepPhase.idle);
      expect(c.interest, isNull);
      expect(c.error, 'Not found.');
    });

    test('captions stay off without the profile setting', () async {
      final rig = protocolRig(interestProtocol(), content: sampleContent());
      addTearDown(rig.dispose);
      final c = rig.controller;
      await rig.toPractice();
      await c.startPractice();
      expect(c.showCaptions, isFalse);
      expect(c.interest!.caption, isNull);
    });
  });

  test('a measurement-only session still ends after the baseline', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.toBaseline();
    await rig.controller.startBaseline();
    await until(() => rig.controller.step == SessionStep.summary, what: 'summary');
    expect(rig.controller.hasProtocol, isFalse);
  });
}

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/application/gradual_practice_controller.dart';
import 'package:participant_app/features/session/application/segment_recorder.dart';
import 'package:participant_app/features/session/domain/practice_trials.dart';

import 'practice_kit.dart';
import 'session_kit.dart';

Future<void> untilPhase(GradualRig rig, GradualPhase phase) =>
    until(() => rig.controller.phase == phase, what: 'phase $phase');

void main() {
  group('stage sequencing', () {
    test('advance: stage 0 runs, trials are posted once, comfort is asked, '
        'the next stage starts', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);

      unawaited0(g.startStage());
      await rig.playStage();

      // The stage is over: trials went up in one batch, then the question.
      expect(g.phase, GradualPhase.comfort);
      expect(rig.repo.trialBatches, hasLength(1));
      expect(rig.repo.trialBatches.single, hasLength(2));
      expect(rig.repo.calls.where((c) => c == 'trials'), hasLength(1));
      expect(rig.repo.stageRequests, isEmpty, reason: 'comfort comes first');

      await g.answerComfort(4);
      expect(g.phase, GradualPhase.decision);
      expect(rig.repo.stageRequests, [(stageIndex: 0, comfort: 4)]);
      expect(g.decisionMessage, contains('Next comes a new picture'));

      // The comfort answer went up as an event with the stage index.
      final event = rig.repo.events.single;
      expect(event.type, SessionEventType.comfortAnswer);
      expect(event.payload, {'value': 4, 'stage_index': 0});

      await g.continueAfterDecision();
      expect(g.stageIndex, 1);
      await untilPhase(rig, GradualPhase.trial);
      expect(g.stage.numberZone, NumberZone.faceEdge);
      // Segment lifecycle: opened for stage 0 with its index, closed before
      // the trials were posted, opened again for stage 1.
      expect(rig.recorder.calls.take(3), ['open:practice:0', 'close:practice', 'open:practice:1']);
    });

    test('a trial carries what the server needs', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage();

      final trials = rig.repo.trialBatches.single;
      for (var i = 0; i < trials.length; i++) {
        final t = trials[i];
        expect(t.stageIndex, 0);
        expect(t.trialIndex, i);
        expect(t.zone, 'outside');
        expect(t.faceLevel, 0);
        expect(t.response, t.numberShown, reason: 'the fake answered correctly');
        expect(t.responseMs, isNotNull);
        expect(t.tMs, greaterThan(0));
        final json = t.toJson();
        expect((json['position'] as Map).keys, containsAll(['x', 'y']));
      }
    });

    test('hold: the same stage is repeated with a gentle message and '
        'the trial numbers keep counting', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      rig.repo.scriptedDecisions.add(const StageDecision(
        kind: StageDecisionKind.hold,
        nextStageIndex: 0,
        reason: 'accuracy',
      ));

      unawaited0(g.startStage());
      await rig.playStage(answer: (shown) => shown == '1' ? '2' : '1');
      await g.answerComfort(3);
      expect(g.decision!.kind, StageDecisionKind.hold);
      expect(g.decisionMessage, "Let's do this one again.");
      expect(g.decisionMessage.toLowerCase(), isNot(contains('wrong')));

      await g.continueAfterDecision();
      expect(g.stageIndex, 0, reason: 'same stage');
      await rig.playStage();
      expect(rig.repo.trialBatches, hasLength(2));
      expect(
        [for (final t in rig.repo.trialBatches[1]) t.trialIndex],
        [2, 3],
        reason: 'trial numbers continue across attempts of one stage',
      );
      expect(rig.recorder.opened.map((o) => o.stage), [0, 0]);
    });

    test('wrong answers are recorded and simply move on', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage(answer: (shown) => shown == '9' ? '8' : '9');

      final trials = rig.repo.trialBatches.single;
      expect(trials, hasLength(2), reason: 'the stage ran to its end anyway');
      expect(trials.every((t) => t.response != t.numberShown), isTrue);
      expect(g.error, isNull);
      expect(g.phase, GradualPhase.comfort);
    });

    test('easier: goes back one stage', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      rig.repo.scriptedDecisions
        ..add(const StageDecision(kind: StageDecisionKind.advance, nextStageIndex: 1))
        ..add(const StageDecision(
          kind: StageDecisionKind.easier,
          nextStageIndex: 0,
          reason: 'low_comfort',
        ));

      unawaited0(g.startStage());
      await rig.playStage();
      await g.answerComfort(4);
      await g.continueAfterDecision();
      expect(g.stageIndex, 1);
      await rig.playStage();
      await g.answerComfort(2);
      expect(g.decision!.kind, StageDecisionKind.easier);
      expect(g.decisionMessage, contains('gentler'));
      await g.continueAfterDecision();
      expect(g.stageIndex, 0);
      await untilPhase(rig, GradualPhase.trial);
      expect(rig.recorder.opened.map((o) => o.stage), [0, 1, 0]);
    });

    test('stop: ends politely and reports the practice as stopped', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      rig.repo.scriptedDecisions.add(const StageDecision(
        kind: StageDecisionKind.stop,
        reason: 'low_comfort_twice',
      ));

      unawaited0(g.startStage());
      await rig.playStage();
      await g.answerComfort(1);
      expect(g.decisionMessage, contains("Let's stop here"));
      expect(g.decisionButton, 'Finish');
      expect(rig.finished, isEmpty);

      await g.continueAfterDecision();
      expect(g.phase, GradualPhase.finished);
      expect(g.end, PracticeEnd.stopped);
      expect(rig.finished, [PracticeEnd.stopped]);
    });

    test('complete: the last stage ends the practice', () async {
      final rig = GradualRig(
        protocol: gradualProtocol(stages: const [
          GradualStage(trials: 1, trialSeconds: 50),
        ]),
      );
      final g = rig.controller;
      addTearDown(g.dispose);
      rig.repo.scriptedDecisions.add(const StageDecision(
        kind: StageDecisionKind.complete,
        reason: 'all_stages_done',
      ));

      unawaited0(g.startStage());
      await rig.playStage();
      await g.answerComfort(5);
      expect(g.decisionMessage, contains('finished the practice'));
      await g.continueAfterDecision();
      expect(g.end, PracticeEnd.completed);
      expect(rig.finished, [PracticeEnd.completed]);
    });

    test('an advance beyond the last stage completes instead of crashing',
        () async {
      final rig = GradualRig(
        protocol: gradualProtocol(stages: const [
          GradualStage(trials: 1, trialSeconds: 50),
        ]),
      );
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage();
      await g.answerComfort(5);
      // The default fake decision is "advance to stage 1".
      await g.continueAfterDecision();
      expect(g.end, PracticeEnd.completed);
    });
  });

  group('comfort', () {
    test('is asked after every stage when the protocol says so', () async {
      final rig = GradualRig(protocol: gradualProtocol(askEveryStage: true));
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage();
      expect(g.phase, GradualPhase.comfort);
      expect(g.comfort.labels, hasLength(5));
    });

    test('is not asked when the protocol does not ask every stage', () async {
      final rig = GradualRig(protocol: gradualProtocol(askEveryStage: false));
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage();
      await untilPhase(rig, GradualPhase.decision);
      expect(rig.repo.stageRequests, [(stageIndex: 0, comfort: null)]);
      expect(rig.repo.events, isEmpty, reason: 'no comfort_answer event');
    });

    test('can be skipped: the stage result goes without a comfort value',
        () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage();
      await g.skipComfort();
      expect(rig.repo.stageRequests, [(stageIndex: 0, comfort: null)]);
      expect(rig.repo.events, isEmpty);
      expect(g.phase, GradualPhase.decision);
    });
  });

  group('trials', () {
    test('a trial that times out is recorded without a response', () async {
      final rig = GradualRig(
        protocol: gradualProtocol(stages: const [
          GradualStage(trials: 2, trialSeconds: 2), // 20 ms
        ]),
      );
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await untilPhase(rig, GradualPhase.comfort);

      final trials = rig.repo.trialBatches.single;
      expect(trials, hasLength(2));
      expect(trials.every((t) => t.response == null && t.responseMs == null), isTrue);
    });

    test('four-choice options always include the shown number', () async {
      final rig = GradualRig(
        protocol: gradualProtocol(stages: const [
          GradualStage(
            trials: 8,
            trialSeconds: 50,
            responseMode: StageResponseMode.fourChoice,
          ),
        ]),
      );
      final g = rig.controller;
      addTearDown(g.dispose);
      final seen = <List<String>>[];
      g.addListener(() {
        final s = g.stimulus;
        if (g.phase == GradualPhase.trial && s != null) {
          expect(s.input, TrialInput.fourChoice);
          expect(s.options, contains(s.shown));
          expect(s.options, hasLength(4));
          seen.add(s.options);
        }
      });
      unawaited0(g.startStage());
      await rig.playStage();
      expect(seen.length, greaterThanOrEqualTo(8));
    });

    test('symbol mode shows a symbol name as number_shown', () async {
      final rig = GradualRig(
        protocol: gradualProtocol(stages: const [
          GradualStage(
            trials: 3,
            trialSeconds: 50,
            responseMode: StageResponseMode.symbol,
          ),
        ]),
      );
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage();
      final trials = rig.repo.trialBatches.single;
      expect(trials.every((t) => kSymbolNames.contains(t.numberShown)), isTrue);
    });

    test('the profile response mode applies to "profile" stages', () async {
      final rig = GradualRig(profileMode: ResponseMode.fourChoice);
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await untilPhase(rig, GradualPhase.trial);
      expect(g.input, TrialInput.fourChoice);
      expect(g.stimulus!.options, contains(g.stimulus!.shown));
    });

    test('an empty answer is ignored', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await untilPhase(rig, GradualPhase.trial);
      g.submit('  ');
      await settle();
      expect(g.phase, GradualPhase.trial);
    });

    test('the numbers land in the stage zone', () async {
      final rig = GradualRig(
        protocol: gradualProtocol(stages: const [
          GradualStage(
            trials: 4,
            trialSeconds: 50,
            numberZone: NumberZone.nearEyes,
          ),
        ]),
      );
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await rig.playStage();
      final eye = g.layout.eyeRegion;
      for (final t in rig.repo.trialBatches.single) {
        expect(t.zone, 'near_eyes');
        expect(eye.contains(t.x, t.y), isFalse,
            reason: 'the centre of a near_eyes number is not on the eyes');
      }
    });
  });

  group('pause and failures', () {
    test('pausing drops the number on the screen; resuming carries on and '
        'still posts once', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await untilPhase(rig, GradualPhase.trial);

      g.pause();
      expect(g.stimulus, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(g.phase, GradualPhase.trial, reason: 'nothing advanced while paused');

      g.resume();
      await rig.playStage();
      expect(g.phase, GradualPhase.comfort);
      expect(rig.repo.trialBatches, hasLength(1));
      expect(rig.repo.trialBatches.single, hasLength(2));
    });

    test('a failing trial upload shows a message and can be retried',
        () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      rig.repo.trialsFailure = const ApiException('Server busy.', statusCode: 503);

      unawaited0(g.startStage());
      await rig.playStage();
      await untilPhase(rig, GradualPhase.problem);
      expect(g.error, 'Server busy.');

      rig.repo.trialsFailure = null;
      await g.retry();
      expect(g.phase, GradualPhase.comfort);
      expect(rig.repo.trialBatches, hasLength(1));
      expect(rig.recorder.closed, hasLength(1), reason: 'the segment closes once');
    });

    test('an interrupted stage starts again after a recalibration', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      unawaited0(g.startStage());
      await untilPhase(rig, GradualPhase.trial);

      g.interrupted();
      await g.resumeAfterInterruption();
      await rig.playStage();
      expect(rig.recorder.opened, hasLength(2), reason: 'the segment opens again');
      expect(rig.repo.trialBatches, hasLength(1));
    });

    test('a recorder failure is shown and can be retried', () async {
      final rig = GradualRig();
      final g = rig.controller;
      addTearDown(g.dispose);
      rig.recorder.openFailure = const ApiException('Layout refused.', statusCode: 409);
      await g.startStage();
      expect(g.phase, GradualPhase.problem);
      expect(g.error, 'Layout refused.');

      rig.recorder.openFailure = null;
      await g.retry();
      await untilPhase(rig, GradualPhase.trial);
    });
  });

  test('the number lands where the recorder was told the face is', () async {
    final rig = GradualRig();
    final g = rig.controller;
    addTearDown(g.dispose);
    unawaited0(g.startStage());
    await untilPhase(rig, GradualPhase.trial);
    expect(rig.recorder.opened.single.layout, g.layout);
    final r = g.stimulus!.placement.rect;
    expect(g.layout.faceBox.intersects(r), isFalse,
        reason: 'stage 0 is the "outside" zone');
  });
}

void unawaited0(Future<void> f) {}

extension on Box {
  bool intersects(Box o) => x < o.right && right > o.x && y < o.bottom && bottom > o.y;
}

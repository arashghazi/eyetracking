import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/application/interest_practice_controller.dart';
import 'package:participant_app/features/session/application/segment_recorder.dart';

import 'practice_kit.dart';
import 'session_kit.dart';

void main() {
  group('the conversation', () {
    test('plays the start segment, asks its question, follows the branch, '
        'ends at a segment without a question', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);

      i.start();
      expect(i.phase, InterestPhase.playing);
      expect(i.segment!.id, 's1');
      expect(i.videoUrl, '/media/s1');
      expect(i.part, InterestPart.conversation);

      await rig.playCurrent();
      // The segment closed on the recorder, then the question shows.
      expect(rig.recorder.calls, ['open:practice', 'close:practice']);
      expect(i.phase, InterestPhase.question);
      expect(i.question!.prompt, 'Which do you prefer?');
      expect(i.question!.options, ['Trains', 'Planes']);
      expect(i.videoUrl, isNull, reason: 'the video is off while a question shows');

      // The answer goes up as an interaction; the server names the next segment.
      await i.answerInteraction('Planes');
      final answer = rig.repo.answers.single;
      expect(answer.kind, AnswerKind.interaction);
      expect(answer.segmentId, 's1');
      expect(answer.questionId, 'q1');
      expect(answer.option, 'Planes');
      expect(answer.tMs, greaterThan(0));
      expect(i.phase, InterestPhase.playing);
      expect(i.segment!.id, 's2b', reason: 'Planes -> s2b');

      // s2b has no question: the conversation is over.
      await rig.playCurrent();
      expect(i.phase, InterestPhase.comprehension);
      expect(i.part, InterestPart.comprehension);
    });

    test('a segment that follows the other branch', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      await i.answerInteraction('Trains');
      expect(i.segment!.id, 's2');
    });

    test('an answer without a next segment ends the conversation', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      rig.repo.answerResult = (a) => const AnswerResult();
      i.start();
      await rig.playCurrent();
      await i.answerInteraction('Trains');
      expect(i.phase, InterestPhase.comprehension);
    });

    test('the comprehension questions come one by one, then the practice is done',
        () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      await i.answerInteraction('Trains');
      await rig.playCurrent(); // s2, no question

      expect(i.question!.id, 'c1');
      expect(i.comprehensionIndex, 0);
      expect(i.comprehensionCount, 2);
      await i.answerComprehension('Red');
      expect(i.question!.id, 'c2');
      expect(i.comprehensionIndex, 1);
      expect(rig.finished, isEmpty);
      await i.answerComprehension('Rome');

      expect(rig.finished, [PracticeEnd.completed]);
      expect(i.phase, InterestPhase.finished);
      final kinds = [for (final a in rig.repo.answers) a.kind];
      expect(kinds, [
        AnswerKind.interaction,
        AnswerKind.comprehension,
        AnswerKind.comprehension,
      ]);
      // Comprehension answers name the last segment of the conversation.
      expect(rig.repo.answers[1].segmentId, 's2');
      expect(rig.repo.answers[1].questionId, 'c1');
      expect(rig.repo.answers[2].option, 'Rome');
    });

    test('a conversation without comprehension questions finishes at its end',
        () async {
      final content = PersonalizedContent(
        startSegment: 's1',
        segments: const [
          PersonalizedSegment(id: 's1', mediaUrl: '/m/1', faceLayout: testFaceLayout),
        ],
      );
      final rig = InterestRig(content: content);
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      expect(rig.finished, [PracticeEnd.completed]);
    });

    test('the post segment plays prompt-free as the post segment', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      await i.answerInteraction('Trains');
      await rig.playCurrent();
      await i.answerComprehension('Red');
      await i.answerComprehension('Paris');

      i.startPost();
      expect(i.part, InterestPart.post);
      expect(i.segment!.id, 's3');
      expect(i.videoUrl, '/media/s3');
      rig.recorder.calls.clear();
      await rig.playCurrent();

      expect(rig.recorder.calls, ['open:post', 'close:post']);
      expect(rig.postFinished, 1);
      expect(i.phase, InterestPhase.finished);
      expect(rig.repo.answers, hasLength(3), reason: 'no question at the post segment');
    });

    test('with no post segment the last conversation segment is replayed',
        () async {
      final base = sampleContent();
      final content = PersonalizedContent(
        startSegment: base.startSegment,
        segments: base.segments,
        comprehension: const [],
      );
      final rig = InterestRig(content: content);
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      await i.answerInteraction('Trains');
      await rig.playCurrent();
      i.startPost();
      expect(i.segment!.id, 's2');
    });
  });

  group('layout mapping', () {
    test('a normalized face layout maps onto the full video rectangle', () {
      const rect = Box(100, 50, 1000, 500);
      final layout = testFaceLayout.toStimulusLayout(screen1440, rect);
      expect(layout.screen, screen1440);
      expect(layout.faceBox, const Box(400, 100, 400, 400));
      expect(layout.eyeRegion, const Box(400, 175, 400, 100));
      expect(layout.mouthRegion.x, 400);
      expect(layout.mouthRegion.y, 325);
      expect(layout.mouthRegion.w, 400);
      expect(layout.mouthRegion.h, 125);
    });

    test('letterboxing: a 16:9 video in a square-ish window is centred with '
        'bars above and below', () {
      // Player 1000 x 800 at (0, 40); video 1920 x 1080 -> 1000 x 562.5,
      // centred vertically: the picture starts at y = 40 + 118.75.
      final rect = containedVideoRect(const Box(0, 40, 1000, 800), 1920, 1080);
      expect(rect.x, closeTo(0, 1e-9));
      expect(rect.w, closeTo(1000, 1e-9));
      expect(rect.h, closeTo(562.5, 1e-9));
      expect(rect.y, closeTo(158.75, 1e-9));

      final layout = testFaceLayout.toStimulusLayout(screen1440, rect);
      expect(layout.faceBox.y, closeTo(158.75 + 0.1 * 562.5, 1e-9));
      expect(layout.faceBox.h, closeTo(0.8 * 562.5, 1e-9));
      expect(layout.faceBox.x, closeTo(300, 1e-9));
      // The face never leaves the picture, so never lands on a black bar.
      expect(rect.containsBox(layout.faceBox), isTrue);
    });

    test('pillarboxing: a tall video in a wide window is centred with bars '
        'left and right', () {
      final rect = containedVideoRect(const Box(0, 40, 1400, 800), 1080, 1920);
      expect(rect.h, 800);
      expect(rect.w, closeTo(450, 1e-9));
      expect(rect.x, closeTo(475, 1e-9));
    });

    test('an unknown video size falls back to the whole player', () {
      const player = Box(0, 40, 1000, 800);
      expect(containedVideoRect(player, 0, 0), player);
    });

    test('the controller posts the mapped layout when the video plays, and '
        'again when the window is resized', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();

      // The rectangle arrives first, then playback starts.
      i.onVideoRect(const Box(0, 40, 1440, 810));
      expect(rig.recorder.opened, isEmpty, reason: 'not before the video plays');
      i.onVideoPlaying();
      await settle();
      final first = rig.recorder.opened.single;
      expect(first.segment, SessionSegmentName.practice);
      expect(first.layout.faceBox, const Box(432, 121, 576, 648));

      // Resize: a smaller, letterboxed picture -> the layout is posted again.
      i.onVideoRect(const Box(200, 40, 720, 405));
      await settle();
      expect(rig.recorder.updated, hasLength(1));
      expect(rig.recorder.updated.single.layout.faceBox,
          const Box(200 + 0.3 * 720, 40 + 0.1 * 405, 0.4 * 720, 0.8 * 405));
      expect(rig.recorder.opened, hasLength(1), reason: 'still the same segment');
    });

    test('a segment without a face layout plays but records nothing', () async {
      final content = PersonalizedContent(
        startSegment: 's1',
        segments: const [PersonalizedSegment(id: 's1', mediaUrl: '/m/1')],
      );
      final rig = InterestRig(content: content);
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      expect(rig.recorder.calls, isEmpty);
    });

    test('nothing is recorded before the video really plays', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      i.onVideoRect(const Box(0, 40, 1440, 810));
      await settle();
      expect(rig.recorder.calls, isEmpty);
    });
  });

  group('problems and captions', () {
    test('a video that fails shows "not ready"; retrying reloads the links '
        'and plays the same segment again', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await i.onVideoError('The video could not be loaded.');
      expect(i.videoProblem, 'The video is not ready');
      expect(i.videoUrl, isNull);

      await i.retryVideo();
      expect(rig.reloads, 1);
      expect(i.videoProblem, isNull);
      expect(i.segment!.id, 's1');
      expect(i.videoUrl, '/media/s1-fresh', reason: 'fresh signed link');
    });

    test('a segment that was recording is closed when its video fails',
        () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      i.onVideoRect(const Box(0, 40, 1440, 810));
      i.onVideoPlaying();
      await settle();
      await i.onVideoError('x');
      expect(rig.recorder.calls, ['open:practice', 'close:practice']);
    });

    test('a segment whose file was never uploaded is "not ready" at once',
        () async {
      final content = PersonalizedContent(
        startSegment: 's1',
        segments: const [PersonalizedSegment(id: 's1', mediaUrl: '')],
      );
      final rig = InterestRig(content: content);
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      expect(i.videoProblem, 'The video is not ready');
      expect(i.videoUrl, isNull);
    });

    test('captions show the personalized text only when asked for', () {
      final off = InterestRig()..controller.start();
      addTearDown(off.controller.dispose);
      expect(off.controller.caption, isNull);

      final on = InterestRig(showCaptions: true)..controller.start();
      addTearDown(on.controller.dispose);
      expect(on.controller.caption, 'Hi Sam, today we talk about trains.');
    });

    test('a failing answer keeps the question and shows the message', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      rig.repo.answerResult = (a) =>
          throw const ApiException('Server busy.', statusCode: 503);
      await i.answerInteraction('Trains');
      expect(i.phase, InterestPhase.question);
      expect(i.error, 'Server busy.');
      expect(i.busy, isFalse);
    });

    test('pausing takes the video off; resuming plays the segment again',
        () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      final before = i.videoAttempt;
      i.pause();
      expect(i.videoUrl, isNull);
      i.resume();
      expect(i.videoUrl, '/media/s1');
      expect(i.videoAttempt, greaterThan(before));
    });
  });
}

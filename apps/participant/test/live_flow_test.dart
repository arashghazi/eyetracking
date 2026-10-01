import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/application/live_practice_controller.dart';
import 'package:participant_app/features/session/domain/session_step.dart';

import 'live_kit.dart';
import 'practice_kit.dart';
import 'session_kit.dart';

/// The live path through the session flow: baseline, practice (the
/// conversation), post observation, comfort and summary, with the same
/// pause, end and device-change handling as the other paths.
void main() {
  Future<Rig> liveRig({
    FakeLiveRepository? live,
    FakeSpeechSynthesizer? speech,
    FakeAudioRecorder? microphone,
    double postSeconds = 5,
  }) async {
    final rig = protocolRig(
      liveProtocol(baselineSeconds: 30, postSeconds: postSeconds),
      live: live,
      speech: speech,
      microphone: microphone,
    );
    addTearDown(rig.dispose);
    await rig.toPractice();
    return rig;
  }

  Future<void> playVideo(SessionFlowControllerHandle h) async {
    h.live.onVideoRect(const Box(0, 40, 1440, 810));
    h.live.onVideoPlaying();
    await until(() => h.rig.controller.frameSource.isActive, what: 'camera');
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  test('the protocol says it is live; the practice step waits for Start',
      () async {
    final rig = await liveRig();
    final c = rig.controller;
    expect(c.isLive, isTrue);
    expect(c.isInterest, isFalse);
    expect(c.step, SessionStep.practice);
    expect(c.phase, StepPhase.idle);
    expect(c.live, isNull);
    expect(c.practiceVisible, isFalse);
  });

  test('practice, post observation, comfort and summary', () async {
    final live = FakeLiveRepository(maxTurns: 2);
    final rig = await liveRig(live: live);
    final c = rig.controller;

    await c.startPractice();
    final l = c.live!;
    expect(c.phase, StepPhase.running);
    expect(c.practiceVisible, isTrue);
    await until(() => l.phase == LivePhase.choose, what: 'the choice card');
    expect(rig.repo.layouts.where((x) => x.segment == SessionSegmentName.practice),
        isEmpty, reason: 'nothing is recorded while choosing');

    await l.begin();
    expect(l.phase, LivePhase.conversation);
    final h = SessionFlowControllerHandle(rig, l);
    await playVideo(h);
    // The practice segment is open with the layout mapped from face_layout.
    final practiceLayout = rig.repo.layouts.last;
    expect(practiceLayout.segment, SessionSegmentName.practice);
    expect(practiceLayout.stageIndex, isNull);
    expectBox(practiceLayout.layout.faceBox, const Box(432, 121, 576, 648));
    expectBox(practiceLayout.layout.eyeRegion, const Box(432, 242.5, 576, 162));
    expectBox(
        practiceLayout.layout.mouthRegion, const Box(432, 485.5, 576, 202.5));

    await l.send('I like steam trains');
    await l.send('The big ones');
    expect(l.phase, LivePhase.ended, reason: 'the last allowed turn');
    expect(c.step, SessionStep.practice, reason: 'Continue is the participant\'s');
    await l.continueAfterEnd();
    expect(c.step, SessionStep.post);
    expect(c.phase, StepPhase.idle);
    expect(rig.repo.events.last.type, SessionEventType.segmentEnd);
    expect(rig.repo.events.last.payload, {'segment': 'practice'});

    await c.startPost();
    expect(c.practiceVisible, isTrue);
    expect(l.phase, LivePhase.post);
    await playVideo(h);
    expect(rig.repo.layouts.last.segment, SessionSegmentName.post);
    expectBox(rig.repo.layouts.last.layout.faceBox, const Box(432, 121, 576, 648));

    // The post observation is timed by the protocol (5 s here, shortened).
    l.cancel();
    await c.endEarly();
    expect(c.step, SessionStep.summary);

    final types = rig.repo.events.map((e) => e.type.wire).toList();
    expect(types.last, 'end');
    final segments = [
      for (final e in rig.repo.events)
        if (e.type == SessionEventType.segmentStart ||
            e.type == SessionEventType.segmentEnd)
          '${e.type.wire}:${e.payload!['segment']}',
    ];
    expect(segments.take(4), [
      'segment_start:baseline',
      'segment_end:baseline',
      'segment_start:practice',
      'segment_end:practice',
    ]);
    expect(segments, contains('segment_start:post'));
    expect(rig.repo.sampleCount, greaterThan(0));
  });

  test('the post observation runs for the protocol time, then asks comfort',
      () async {
    final rig = protocolRig(
      liveProtocol(postSeconds: 5),
      timing: practiceTiming, // one protocol second is 10 ms
    );
    addTearDown(rig.dispose);
    await rig.toPractice();
    final c = rig.controller;
    await c.startPractice();
    final l = c.live!;
    await until(() => l.phase == LivePhase.choose, what: 'the choice card');
    await l.begin();
    await l.endConversation();
    await l.continueAfterEnd();
    await c.startPost();
    expect(c.postDuration, const Duration(milliseconds: 50));
    await playVideo(SessionFlowControllerHandle(rig, l));
    await until(() => c.askingComfort, what: 'the comfort question');
    await c.answerFinalComfort(4);
    expect(c.step, SessionStep.summary);
    expect(rig.repo.events.map((e) => e.type.wire),
        containsAllInOrder(['segment_start', 'segment_end', 'comfort_answer', 'end']));
    expect(
      rig.repo.events.where((e) =>
          e.payload?['segment'] == 'post' &&
          (e.type == SessionEventType.segmentStart ||
              e.type == SessionEventType.segmentEnd)),
      hasLength(2),
    );
  });

  test('pause takes the conversation off the screen and stops the avatar; '
      'resume brings it back', () async {
    final speech = FakeSpeechSynthesizer();
    final rig = await liveRig(speech: speech);
    final c = rig.controller;
    await c.startPractice();
    final l = c.live!;
    await until(() => l.phase == LivePhase.choose, what: 'the choice card');
    await l.begin();
    await playVideo(SessionFlowControllerHandle(rig, l));
    final cancels = speech.cancelCount;

    await c.pause();
    expect(c.phase, StepPhase.paused);
    expect(c.practiceVisible, isFalse);
    expect(l.paused, isTrue);
    expect(l.videoUrl, isNull);
    expect(speech.cancelCount, greaterThan(cancels));
    expect(rig.repo.eventTypes, contains(SessionEventType.pause));

    await c.resume();
    expect(c.phase, StepPhase.running);
    expect(l.paused, isFalse);
    expect(l.videoUrl, liveAvatarUrl);
    expect(rig.repo.eventTypes, contains(SessionEventType.resume));
    expect(l.phase, LivePhase.conversation);
  });

  test('pausing while choosing loses nothing', () async {
    final rig = await liveRig();
    final c = rig.controller;
    await c.startPractice();
    final l = c.live!;
    await until(() => l.phase == LivePhase.choose, what: 'the choice card');
    await c.pause();
    expect(c.phase, StepPhase.paused);
    await c.resume();
    expect(l.phase, LivePhase.choose);
    expect(rig.repo.eventTypes, isNot(contains(SessionEventType.pause)),
        reason: 'no segment is open, so the server is not told');
  });

  test('ending the session during the conversation stops the avatar and the '
      'microphone and ends the session', () async {
    final speech = FakeSpeechSynthesizer();
    final mic = FakeAudioRecorder();
    final rig = await liveRig(speech: speech, microphone: mic);
    final c = rig.controller;
    await c.startPractice();
    final l = c.live!;
    await until(() => l.phase == LivePhase.choose, what: 'the choice card');
    l.chooseMode(LiveInputMode.speech);
    await l.begin();
    await playVideo(SessionFlowControllerHandle(rig, l));
    await l.startRecording();
    expect(l.recording, isTrue);

    await c.endEarly();
    expect(c.step, SessionStep.summary);
    expect(rig.repo.eventTypes.last, SessionEventType.end);
    expect(rig.repo.events.last.payload, {'reason': 'ended_early'});
    await settle();
    expect(mic.cancelCount, 1, reason: 'the microphone was released');
    expect(speech.cancelCount, greaterThan(0));
  });

  test('a device change interrupts the conversation; after calibrating again '
      'it goes on where it was', () async {
    final rig = await liveRig();
    final c = rig.controller;
    await c.startPractice();
    final l = c.live!;
    await until(() => l.phase == LivePhase.choose, what: 'the choice card');
    await l.begin();
    await playVideo(SessionFlowControllerHandle(rig, l));
    await l.send('hello');

    rig.frames.emitEvent(FrameSourceEvent.cameraChanged);
    await until(() => c.phase == StepPhase.changed, what: 'the change');
    expect(l.videoUrl, isNull);
    await until(
      () => rig.repo.eventTypes.contains(SessionEventType.cameraChanged),
      what: 'the change event',
    );

    c.recalibrate();
    await c.startCalibration();
    c.continueToValidation();
    await c.startValidation();
    c.continueToBaseline();
    expect(c.step, SessionStep.practice, reason: 'the baseline is not repeated');

    await c.startPractice();
    expect(c.live, same(l), reason: 'the same conversation');
    expect(l.phase, LivePhase.conversation);
    expect(l.turnsUsed, 1);
    expect(l.videoUrl, liveAvatarUrl);
    expect(rig.repo.sampleCount, greaterThanOrEqualTo(0));
  });

  test('the closing line the server omits is filled from the protocol, with '
      'the name and the topic', () async {
    final live = FakeLiveRepository(maxTurns: 1)..closingWithoutText = true;
    final rig = protocolRig(
      liveProtocol(
        live: const LiveProtocolConfig(
          closingLine: 'Thanks for the chat about {{topic}}, {{display_name}}!',
        ),
      ),
      live: live,
      profile: const Profile(displayName: 'Sam'),
    );
    addTearDown(rig.dispose);
    await rig.toPractice();
    await rig.controller.startPractice();
    final l = rig.controller.live!;
    await until(() => l.phase == LivePhase.choose, what: 'the choice card');
    await l.begin();
    await l.send('hello');
    expect(l.caption, 'Thanks for the chat about trains, Sam!');
  });

  test('without the live port the practice says it is not available',
      () async {
    final rig = Rig(
      timing: practiceTiming,
      assignment: assignmentFor(ProtocolPath.liveConversation),
      profile: null,
    );
    addTearDown(rig.dispose);
    rig.repo.protocolForCreate = ProtocolRef(
      id: '7',
      name: 'Live',
      version: 1,
      path: ProtocolPath.liveConversation,
      definition: liveProtocol(),
    );
    await rig.toPractice();
    await rig.controller.startPractice();
    expect(rig.controller.live, isNull);
    expect(rig.controller.error, contains('not available'));
    expect(rig.controller.phase, StepPhase.idle);
  });
}

/// A flow rig together with the live controller it runs.
class SessionFlowControllerHandle {
  SessionFlowControllerHandle(this.rig, this.live);

  final Rig rig;
  final LivePracticeController live;
}

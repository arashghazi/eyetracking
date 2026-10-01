import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/application/live_practice_controller.dart';
import 'package:participant_app/features/session/application/segment_recorder.dart';

import 'live_kit.dart';
import 'practice_kit.dart';
import 'session_kit.dart';

void main() {
  group('before the conversation', () {
    test('loads what may be chosen: typing always, speech and the transcript '
        'only when the protocol offers them', () async {
      final rig = LiveRig(
        repo: FakeLiveRepository(storeTranscriptOffered: true),
      );
      addTearDown(rig.controller.dispose);
      expect(rig.controller.phase, LivePhase.loading);
      await rig.controller.load();
      final c = rig.controller;
      expect(c.phase, LivePhase.choose);
      expect(c.offersSpeech, isTrue);
      expect(c.storeTranscriptOffered, isTrue);
      expect(c.mode, LiveInputMode.typed);
      expect(c.allowTranscript, isFalse, reason: 'unchecked by default');
      expect(rig.repo.calls, ['snapshot']);
    });

    test('speech is not offered when the protocol lists typing only', () async {
      final rig = LiveRig(
        repo: FakeLiveRepository(inputModes: const [LiveInputMode.typed]),
      );
      addTearDown(rig.controller.dispose);
      await rig.controller.load();
      expect(rig.controller.offersSpeech, isFalse);
      expect(rig.controller.storeTranscriptOffered, isFalse);
      rig.controller.chooseMode(LiveInputMode.speech);
      expect(rig.controller.mode, LiveInputMode.typed,
          reason: 'speech cannot be chosen when it is not offered');
    });

    test('a failed load says why and can be tried again', () async {
      final rig = LiveRig();
      addTearDown(rig.controller.dispose);
      rig.repo.snapshotFailure =
          const ApiException('Could not reach the server.');
      await rig.controller.load();
      expect(rig.controller.phase, LivePhase.loading);
      expect(rig.controller.loadError, 'Could not reach the server.');
      rig.repo.snapshotFailure = null;
      await rig.controller.load();
      expect(rig.controller.phase, LivePhase.choose);
      expect(rig.controller.loadError, isNull);
    });

    test('starts a typed conversation: the choices are sent, the opening line '
        'is the caption and is spoken', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      expect(rig.repo.starts.single.mode, LiveInputMode.typed);
      expect(rig.repo.starts.single.allowTranscript, isFalse);
      expect(rig.repo.starts.single.tMs, greaterThan(0));
      expect(c.phase, LivePhase.conversation);
      expect(c.caption, 'Hi Sam! What do you like most about trains?');
      expect(rig.speech.spoken, [c.caption]);
      expect(c.turnsLeft, 4);
      expect(c.turnsUsed, 0);
      expect(c.avatar!.synthetic, isTrue);
      expect(c.videoUrl, liveAvatarUrl);
      expect(c.typing, isTrue);
      expect(c.speechMode, isFalse);
    });

    test('agreeing to a written record is sent only when it is offered',
        () async {
      final offered = LiveRig(
        repo: FakeLiveRepository(storeTranscriptOffered: true),
      );
      addTearDown(offered.controller.dispose);
      await offered.controller.load();
      offered.controller.setAllowTranscript(true);
      await offered.controller.begin();
      expect(offered.repo.starts.single.allowTranscript, isTrue);
      expect(offered.repo.conversation!.transcriptAllowed, isTrue);

      final notOffered = LiveRig();
      addTearDown(notOffered.controller.dispose);
      await notOffered.controller.load();
      notOffered.controller.setAllowTranscript(true);
      await notOffered.controller.begin();
      expect(notOffered.repo.starts.single.allowTranscript, isFalse,
          reason: 'never agreed to something that was not asked');
    });

    test('a refusal to start (speech is not available) stays on the card',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.chooseMode(LiveInputMode.speech);
      rig.repo.startFailure = const ApiException(
        'speech is not available right now; please choose typing',
        statusCode: 409,
      );
      await c.begin();
      expect(c.phase, LivePhase.choose);
      expect(c.error, 'speech is not available right now; please choose typing');
      expect(c.busy, isFalse);
      // Typing then works.
      rig.repo.startFailure = null;
      c.chooseMode(LiveInputMode.typed);
      expect(c.error, isNull);
      await c.begin();
      expect(c.phase, LivePhase.conversation);
    });
  });

  group('typed turns', () {
    test('send expect_turn = turns used, show the reply, count down and speak',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();

      expect(await c.send('  I like steam trains  '), isTrue);
      expect(rig.repo.typed.single.expectTurn, 0);
      expect(rig.repo.typed.single.text, 'I like steam trains',
          reason: 'trimmed');
      expect(c.turnsUsed, 1);
      expect(c.turnsLeft, 3);
      expect(c.heard, 'I like steam trains');
      expect(c.caption, 'Reply 1: tell me more about trains.');
      expect(rig.speech.spoken.last, c.caption);

      expect(await c.send('The big ones'), isTrue);
      expect(rig.repo.typed.last.expectTurn, 1);
      expect(c.turnsLeft, 2);
      expect(c.turns.length, 5, reason: 'opening + 2 x (you, avatar)');
    });

    test('an empty message is not sent', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      expect(await c.send('   '), isFalse);
      expect(rig.repo.typed, isEmpty);
    });

    test('a message over the limit is not sent', () async {
      final rig = LiveRig(repo: FakeLiveRepository(maxChars: 50));
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      expect(await c.send('x' * 51), isFalse);
      expect(rig.repo.typed, isEmpty);
      expect(c.error, contains('50'));
    });

    test('the input is off while a turn is in flight, and a double send is '
        'ignored', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      final gate = rig.repo.gate = Completer<void>();
      final first = c.send('one');
      await settle();
      expect(c.busy, isTrue);
      expect(c.canSend, isFalse);
      expect(await c.send('two'), isFalse);
      gate.complete();
      expect(await first, isTrue);
      expect(rig.repo.typed.length, 1);
      expect(c.canSend, isTrue);
    });

    test('Voice off silences the lines; Voice on speaks them again', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      expect(c.voiceOn, isTrue);
      expect(rig.speech.spoken.length, 1);
      c.toggleVoice();
      expect(c.voiceOn, isFalse);
      expect(rig.speech.cancelCount, greaterThan(0));
      await c.send('one');
      expect(rig.speech.spoken.length, 1, reason: 'the reply stays silent');
      expect(c.caption, startsWith('Reply 1'), reason: 'but is still shown');
      c.toggleVoice();
      await c.send('two');
      expect(rig.speech.spoken.last, startsWith('Reply 2'));
    });
  });

  group('errors', () {
    test('a 409 is shown as written with a Reload; reloading continues where '
        'the server is', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      // The server already has one turn the app did not see.
      rig.repo.seedOpen(used: 1);
      expect(await c.send('hello'), isFalse);
      expect(c.error, 'this turn was already sent; reload the conversation');
      expect(c.conflict, isTrue);
      expect(c.turnsUsed, 0);

      await c.reload();
      expect(c.error, isNull);
      expect(c.conflict, isFalse);
      expect(c.turnsUsed, 1);
      expect(c.turnsLeft, 3);
      expect(c.phase, LivePhase.conversation);
      expect(c.caption, 'Reply 1');

      expect(await c.send('hello again'), isTrue);
      expect(rig.repo.typed.last.expectTurn, 1);
    });

    test('a 422 is shown as written, is not a conflict and keeps the draft '
        '(send returns false)', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      rig.repo.turnFailures.add(const ApiException(
        'say or type something first',
        statusCode: 422,
      ));
      expect(await c.send('hmm'), isFalse);
      expect(c.error, 'say or type something first');
      expect(c.conflict, isFalse);
      c.dismissError();
      expect(c.error, isNull);
      expect(await c.send('hmm'), isTrue);
    });

    test('a network failure can be tried again', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      rig.repo.turnFailures.add(const ApiException(
          'Could not reach the server. Check your connection and try again.'));
      expect(await c.send('hi'), isFalse);
      expect(c.error, startsWith('Could not reach the server'));
      expect(c.conflict, isFalse);
      expect(c.busy, isFalse);
      expect(await c.send('hi'), isTrue);
      expect(c.error, isNull);
    });

    test('reloading a conversation that ended on the server ends it here',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      rig.repo.seedClosed(reason: LiveEndReason.timeLimit);
      expect(await c.send('hello'), isFalse);
      expect(c.conflict, isTrue);
      await c.reload();
      expect(c.phase, LivePhase.ended);
      expect(c.endReason, LiveEndReason.timeLimit);
      expect(c.caption, isNotNull);
    });
  });

  group('distress', () {
    test('a distress flag offers a break; Keep talking hides it', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      expect(c.distress, isFalse);
      rig.repo.distressOnNext = true;
      await c.send('I feel scared');
      expect(c.distress, isTrue);
      c.dismissDistress();
      expect(c.distress, isFalse);
    });

    test('the offer goes away with the next turn and when paused', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      rig.repo.distressOnNext = true;
      await c.send('I feel scared');
      expect(c.distress, isTrue);
      await c.send('I am ok now');
      expect(c.distress, isFalse);
      rig.repo.distressOnNext = true;
      await c.send('scared again');
      expect(c.distress, isTrue);
      c.pause();
      expect(c.distress, isFalse);
    });
  });

  group('ending', () {
    test('End conversation closes it, shows the closing line and waits for '
        'Continue', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      await rig.playVideo();
      await c.send('hello');
      await c.endConversation();
      expect(rig.repo.endCalls, 1);
      expect(c.phase, LivePhase.ended);
      expect(c.endReason, LiveEndReason.participantEnded);
      expect(c.caption, 'Thank you for talking with me about trains.');
      expect(rig.speech.spoken.last, c.caption);
      expect(c.turnsLeft, 0);
      expect(c.canSend, isFalse);
      expect(await c.send('more'), isFalse);
      expect(rig.finished, isEmpty, reason: 'not before Continue');

      await c.continueAfterEnd();
      expect(c.phase, LivePhase.finished);
      expect(rig.finished, [PracticeEnd.completed]);
      expect(rig.recorder.calls, ['open:practice', 'close:practice']);
    });

    test('the last allowed turn ends it with the closing line', () async {
      final rig = LiveRig(repo: FakeLiveRepository(maxTurns: 2));
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      await c.send('one');
      expect(c.phase, LivePhase.conversation);
      await c.send('two');
      expect(c.phase, LivePhase.ended);
      expect(c.endReason, LiveEndReason.turnLimit);
      expect(c.caption, 'Thank you for talking with me about trains.');
      expect(c.turnsLeft, 0);
    });

    test('a closing turn that comes without its text uses the protocol line',
        () async {
      final rig = LiveRig(
        repo: FakeLiveRepository(maxTurns: 1)..closingWithoutText = true,
      );
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      await c.send('one');
      expect(c.phase, LivePhase.ended);
      expect(c.caption, 'Thank you, Sam.');
      expect(rig.speech.spoken.last, 'Thank you, Sam.');

      final ended = LiveRig(repo: FakeLiveRepository()..closingWithoutText = true);
      addTearDown(ended.controller.dispose);
      await ended.startTyped();
      await ended.controller.endConversation();
      expect(ended.controller.caption, 'Thank you, Sam.');
    });

    test('a refused End shows the message and keeps the conversation open',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      rig.repo.endFailure = const ApiException('Try again in a moment.');
      await c.endConversation();
      expect(c.phase, LivePhase.conversation);
      expect(c.error, 'Try again in a moment.');
    });

    test('a conversation that already ended on the server finishes the '
        'practice without starting again', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      rig.repo.seedClosed();
      await c.load();
      expect(c.phase, LivePhase.finished);
      expect(rig.finished, [PracticeEnd.completed]);
      expect(rig.repo.calls, ['snapshot']);
    });
  });

  group('resuming', () {
    test('an open conversation continues where it was, without reading the '
        'opening out again', () async {
      final repo = FakeLiveRepository()..seedOpen(used: 2);
      final rig = LiveRig(repo: repo);
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      expect(rig.repo.calls, ['snapshot', 'start']);
      expect(c.phase, LivePhase.conversation);
      expect(c.turnsUsed, 2);
      expect(c.turnsLeft, 2);
      expect(c.caption, 'Reply 2');
      expect(c.heard, 'message 2');
      expect(rig.speech.spoken, isEmpty);
      await c.send('next');
      expect(repo.typed.single.expectTurn, 2);
    });

    test('a spoken conversation resumes in speech mode', () async {
      final repo = FakeLiveRepository()..seedOpen(mode: LiveInputMode.speech);
      final rig = LiveRig(repo: repo);
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      expect(c.mode, LiveInputMode.speech);
      expect(c.speechMode, isTrue);
      expect(c.typing, isFalse);
    });
  });

  group('speech mode', () {
    test('a spoken turn is uploaded with expect_turn, the transcript is shown '
        'and the recording is released', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      expect(rig.repo.starts.single.mode, LiveInputMode.speech);
      expect(c.speechMode, isTrue);
      expect(c.typing, isFalse);

      await c.startRecording();
      expect(c.recording, isTrue);
      expect(rig.mic.startCount, 1);
      expect(rig.speech.cancelCount, greaterThan(0),
          reason: 'the avatar is silenced while recording');
      await c.stopRecording();

      expect(c.recording, isFalse);
      final sent = rig.repo.audio.single;
      expect(sent.expectTurn, 0);
      expect(sent.clip.bytes, [1, 2, 3, 4]);
      expect(sent.clip.contentType, 'audio/webm;codecs=opus');
      expect(rig.repo.typed, isEmpty, reason: 'nothing typed was sent');
      expect(c.heard, 'I like steam trains');
      expect(c.turnsUsed, 1);
      expect(c.caption, startsWith('Reply 1'));
      expect(rig.speech.spoken.last, c.caption);
      expect(rig.mic.stopCount, 1);
    });

    test('a clip that is too short or empty is not sent', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      rig.mic.clipDuration = const Duration(milliseconds: 100);
      await c.startRecording();
      await c.stopRecording();
      expect(rig.repo.audio, isEmpty);
      expect(c.error, contains('did not hear'));
      c.dismissError();

      rig.mic
        ..clipDuration = const Duration(seconds: 2)
        ..recordNothing = true;
      await c.startRecording();
      await c.stopRecording();
      expect(rig.repo.audio, isEmpty);
      expect(c.error, contains('did not hear'));
    });

    test('a blocked microphone says so and switches to typing', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      rig.mic.startError = const AudioRecorderException(
          'Microphone access was not allowed. Allow it, or type instead.');
      await c.startRecording();
      expect(c.recording, isFalse);
      expect(c.error, contains('not allowed'));
      expect(c.typing, isTrue);
    });

    test('the longest clip stops by itself and is sent', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      await c.startRecording();
      rig.mic.hitLimit();
      await until(() => rig.repo.audio.isNotEmpty, what: 'the upload');
      expect(c.recording, isFalse);
      expect(c.turnsUsed, 1);
    });

    test('letting go before the microphone is ready still sends the clip',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      final gate = rig.mic.startGate = Completer<void>();
      final starting = c.startRecording();
      await settle();
      expect(c.startingRecording, isTrue);
      await c.stopRecording(); // released at once
      expect(rig.repo.audio, isEmpty);
      gate.complete();
      await starting;
      await until(() => rig.repo.audio.isNotEmpty, what: 'the upload');
      expect(c.recording, isFalse);
    });

    test('Type instead releases the microphone; Speak instead comes back',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      await c.startRecording();
      c.typeInstead();
      await settle();
      expect(c.typing, isTrue);
      expect(c.recording, isFalse);
      expect(rig.mic.cancelCount, 1);
      expect(rig.repo.audio, isEmpty, reason: 'a cancelled clip is dropped');
      expect(await c.send('typed in a spoken conversation'), isTrue);
      expect(rig.repo.typed.single.expectTurn, 0);
      c.speakInstead();
      expect(c.typing, isFalse);
    });

    test('a device that cannot record falls back to typing', () async {
      final rig = LiveRig(withMicrophone: false);
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      expect(c.speechMode, isFalse);
      expect(c.typing, isTrue);
      await c.startRecording();
      expect(rig.mic.startCount, 0);

      final unsupported = LiveRig();
      addTearDown(unsupported.controller.dispose);
      unsupported.mic.supported = false;
      await unsupported.startSpoken();
      expect(unsupported.controller.speechMode, isFalse);
      expect(unsupported.controller.typing, isTrue);
    });

    test('a refused spoken turn is shown as written and can be tried again',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      rig.repo.turnFailures.add(const ApiException(
        'we could not turn that into text (empty); please try again or type',
        statusCode: 422,
      ));
      await c.startRecording();
      await c.stopRecording();
      expect(c.error, startsWith('we could not turn that into text'));
      expect(c.conflict, isFalse);
      expect(c.turnsUsed, 0);
      c.dismissError();
      await c.startRecording();
      await c.stopRecording();
      expect(c.turnsUsed, 1);
    });

    test('pausing cancels a recording and silences the avatar', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startSpoken();
      await c.startRecording();
      c.pause();
      await settle();
      expect(c.recording, isFalse);
      expect(rig.mic.cancelCount, 1);
      expect(rig.repo.audio, isEmpty);
    });
  });

  group('the recorded segment', () {
    test('the face layout is posted mapped onto where the video is drawn',
        () async {
      final rig = LiveRig(screen: const ScreenInfo(w: 1440, h: 900));
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      await rig.playVideo(rect: const Box(100, 50, 1000, 500));

      final opened = rig.recorder.opened.single;
      expect(opened.segment, SessionSegmentName.practice);
      expect(opened.stage, isNull);
      final l = opened.layout;
      expect(l.screen, const ScreenInfo(w: 1440, h: 900));
      // face_box [0.3, 0.1, 0.4, 0.8] of the 1000 x 500 frame at (100, 50).
      expectBox(l.faceBox, const Box(400, 100, 400, 400));
      expectBox(l.eyeRegion, const Box(400, 175, 400, 100));
      expectBox(l.mouthRegion, const Box(400, 325, 400, 125));
    });

    test('the layout is posted again when the video moves, not reopened',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      await rig.playVideo(rect: const Box(0, 40, 1000, 500));
      c.onVideoRect(const Box(0, 40, 600, 300));
      await settle();
      expect(rig.recorder.calls, ['open:practice', 'update:practice']);
      expectBox(rig.recorder.updated.single.layout.faceBox,
          const Box(180, 70, 240, 240));
    });

    test('nothing opens before the picture is moving or without a layout',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      c.onVideoRect(const Box(0, 40, 1000, 500));
      await settle();
      expect(rig.recorder.opened, isEmpty, reason: 'not playing yet');
      c.onVideoPlaying();
      await settle();
      expect(rig.recorder.opened.length, 1);

      final bare = LiveRig(repo: FakeLiveRepository()..faceLayout = null);
      addTearDown(bare.controller.dispose);
      await bare.startTyped();
      await bare.playVideo();
      expect(bare.recorder.opened, isEmpty,
          reason: 'no face layout: no region claims, no segment');
    });

    test('a segment that cannot open shows the message and may open again',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      rig.recorder.openFailure = const ApiException('No valid calibration.');
      await rig.playVideo();
      expect(c.error, 'No valid calibration.');
      rig.recorder.openFailure = null;
      c.onVideoRect(const Box(0, 40, 900, 500));
      await settle();
      expect(rig.recorder.opened.length, 1);
    });

    test('a video that cannot load is reported; the conversation goes on',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      c.onVideoError('x');
      expect(c.videoProblem, isNotNull);
      expect(c.videoUrl, isNull);
      expect(await c.send('still here'), isTrue);
      c.retryVideo();
      expect(c.videoProblem, isNull);
      expect(c.videoUrl, liveAvatarUrl);
      expect(c.videoAttempt, 1);
    });

    test('pause takes the video off, resume plays it again; a device change '
        'closes the segment on the client side', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      await rig.playVideo();
      c.pause();
      expect(c.videoUrl, isNull);
      expect(rig.speech.cancelCount, greaterThan(0));
      c.resume();
      expect(c.videoUrl, liveAvatarUrl);
      // The open segment stays open across a pause: playing again does not
      // open a second one.
      await rig.playVideo();
      expect(rig.recorder.opened.length, 1);

      c.interrupted();
      expect(c.videoUrl, isNull);
      c.restartCurrent();
      expect(c.videoUrl, liveAvatarUrl);
      await rig.playVideo();
      expect(rig.recorder.opened.length, 2,
          reason: 'after a device change the segment opens afresh');
    });
  });

  group('the post observation', () {
    test('plays the avatar again, records the post segment from the same '
        'layout, then reports it finished', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      await c.endConversation();
      await c.continueAfterEnd();

      c.startPost(const Duration(milliseconds: 60));
      expect(c.phase, LivePhase.post);
      expect(c.videoUrl, liveAvatarUrl);
      await rig.playVideo(rect: const Box(0, 40, 1000, 500));
      final opened = rig.recorder.opened.last;
      expect(opened.segment, SessionSegmentName.post);
      expectBox(opened.layout.faceBox, const Box(300, 90, 400, 400));

      await until(() => rig.postFinished == 1, what: 'the post time to pass');
      expect(c.phase, LivePhase.finished);
      expect(rig.recorder.closed.last, SessionSegmentName.post);
    });

    test('the clock waits for a pause and carries on with what is left',
        () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      c.startPost(const Duration(milliseconds: 120));
      await rig.playVideo();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      c.pause();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(rig.postFinished, 0, reason: 'paused: no time passes');
      c.resume();
      await rig.playVideo();
      await until(() => rig.postFinished == 1, what: 'the rest of the time');
    });

    test('without a picture the clock runs from the start', () async {
      final rig = LiveRig(repo: FakeLiveRepository()..videoUrl = null);
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      expect(c.videoMissing, isTrue);
      c.startPost(const Duration(milliseconds: 40));
      await until(() => rig.postFinished == 1, what: 'the post time to pass');
    });

    test('cancel stops the clock and nothing more is reported', () async {
      final rig = LiveRig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await rig.startTyped();
      c.startPost(const Duration(milliseconds: 40));
      await rig.playVideo();
      c.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(rig.postFinished, 0);
    });
  });
}

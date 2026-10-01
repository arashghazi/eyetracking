import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/app_scope.dart';
import 'package:participant_app/features/assignments/presentation/topic_screen.dart';
import 'package:participant_app/features/session/application/live_practice_controller.dart';
import 'package:participant_app/features/session/application/session_flow_controller.dart';
import 'package:participant_app/features/session/domain/session_step.dart';
import 'package:participant_app/features/session/presentation/session_flow_screen.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'live_kit.dart';
import 'practice_kit.dart';
import 'session_kit.dart';

/// Protocol seconds stay real seconds, as in the other practice screens.
const widgetTiming = SessionTiming(
  countdownStep: Duration(milliseconds: 2),
  settle: Duration(milliseconds: 8),
  calibrationCapture: Duration(milliseconds: 40),
  validationCapture: Duration(milliseconds: 40),
  progressTick: Duration(milliseconds: 10),
  leadIn: Duration(milliseconds: 2),
  interTrial: Duration(milliseconds: 2),
);

/// What a live screen test holds on to.
class LiveScreen {
  LiveScreen({
    required this.rig,
    required this.repo,
    required this.speech,
    required this.mic,
    required this.configs,
  });

  final Rig rig;
  final FakeLiveRepository repo;
  final FakeSpeechSynthesizer speech;
  final FakeAudioRecorder mic;

  /// Every config the video stage was built with.
  final List<VideoStageConfig> configs;

  SessionFlowController get flow => rig.controller;
  LivePracticeController get live => rig.controller.live!;
}

/// A video stage builder that remembers what it was asked to play.
VideoStageBuilder capturingStage(List<VideoStageConfig> sink) {
  final inner = FakeVideoStage.builder();
  return (context, config) {
    sink.add(config);
    return inner(context, config);
  };
}

/// Opens the live practice (after the baseline) and shows it. Stops at the
/// choice card.
Future<LiveScreen> pumpLive(
  WidgetTester tester, {
  double width = 1440,
  double height = 900,
  FakeLiveRepository? repo,
  FakeSpeechSynthesizer? speech,
  FakeAudioRecorder? mic,
  double postSeconds = 60,
  Profile profile = const Profile(displayName: 'Sam'),
}) async {
  useWindow(tester, width, height);
  final server = repo ?? FakeLiveRepository();
  final voice = speech ?? FakeSpeechSynthesizer();
  final microphone = mic ?? FakeAudioRecorder();
  final configs = <VideoStageConfig>[];
  final rig = protocolRig(
    liveProtocol(baselineSeconds: 0.3, postSeconds: postSeconds),
    live: server,
    speech: voice,
    microphone: microphone,
    profile: profile,
    timing: widgetTiming,
    screen: ScreenInfo(w: width, h: height),
  );
  addTearDown(rig.dispose);
  await tester.runAsync(() async {
    await rig.toPractice();
    rig.frames.autoFrames = false;
    await rig.controller.startPractice();
    await until(() => rig.controller.live!.phase == LivePhase.choose,
        what: 'the choice card');
  });
  final bed = TestBed(videoStage: capturingStage(configs));
  await tester.pumpWidget(AppScope(
    dependencies: bed.dependencies,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: SessionFlowScreen(
        key: ValueKey(rig.controller),
        controller: rig.controller,
      ),
    ),
  ));
  await tester.pump();
  return LiveScreen(
    rig: rig,
    repo: server,
    speech: voice,
    mic: microphone,
    configs: configs,
  );
}

/// Pumps until the microtask-driven fakes have answered.
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// Like [settleFrames], with a little real time for what the session flow
/// does with the camera (pause, closing a recorded segment).
Future<void> settleReal(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)));
  await settleFrames(tester);
}

/// Starts a typed conversation from the card.
Future<LiveScreen> pumpConversation(
  WidgetTester tester, {
  double width = 1440,
  double height = 900,
  FakeLiveRepository? repo,
  FakeSpeechSynthesizer? speech,
  FakeAudioRecorder? mic,
  bool spoken = false,
  double postSeconds = 60,
}) async {
  final s = await pumpLive(
    tester,
    width: width,
    height: height,
    repo: repo,
    speech: speech,
    mic: mic,
    postSeconds: postSeconds,
  );
  if (spoken) {
    await tester.tap(find.byKey(const Key('live-mode-speech')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('live-begin')));
  await settleFrames(tester);
  return s;
}

Future<void> typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('live-input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('live-send')));
  await settleFrames(tester);
}

String captionText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('live-caption-text'))).data!;

void main() {
  group('the choice card', () {
    testWidgets('asks how to talk: Type and Speak, what happens to the voice, '
        'no record checkbox when the protocol keeps none', (tester) async {
      final s = await pumpLive(tester, width: 800);
      expect(find.byKey(const Key('live-choice')), findsOneWidget);
      expect(find.text('How would you like to talk?'), findsOneWidget);
      expect(find.byKey(const Key('live-mode-typed')), findsOneWidget);
      expect(find.byKey(const Key('live-mode-speech')), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Speak'), findsOneWidget);
      expect(
        find.text(
            'Your voice is turned into text and the recording is not kept.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('live-transcript')), findsNothing);
      expect(find.text('You will chat about trains.'), findsOneWidget);
      expect(s.repo.calls, ['snapshot'], reason: 'nothing started yet');
      expect(find.byKey(const Key('live-input')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Speak and its explanation are hidden when speech is not '
        'offered', (tester) async {
      await pumpLive(
        tester,
        width: 800,
        repo: FakeLiveRepository(inputModes: const [LiveInputMode.typed]),
      );
      expect(find.byKey(const Key('live-mode-typed')), findsOneWidget);
      expect(find.byKey(const Key('live-mode-speech')), findsNothing);
      expect(find.text('Speak'), findsNothing);
      expect(find.byKey(const Key('live-speech-note')), findsNothing);
    });

    testWidgets('the written record is offered only when the protocol keeps '
        'transcripts, unchecked, and agreeing is sent', (tester) async {
      final s = await pumpLive(
        tester,
        width: 800,
        repo: FakeLiveRepository(storeTranscriptOffered: true),
      );
      expect(
        find.text('Keep a written record of this conversation for the '
            'research team'),
        findsOneWidget,
      );
      expect(find.text('If you leave it unchecked, only counts are kept.'),
          findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byKey(const Key('live-transcript'))).value,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('live-transcript')));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byKey(const Key('live-transcript'))).value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('live-begin')));
      await settleFrames(tester);
      expect(s.repo.starts.single.allowTranscript, isTrue);
      expect(s.repo.starts.single.mode, LiveInputMode.typed);
    });

    testWidgets('leaving the box unchecked sends false', (tester) async {
      final s = await pumpLive(
        tester,
        width: 800,
        repo: FakeLiveRepository(storeTranscriptOffered: true),
      );
      await tester.tap(find.byKey(const Key('live-begin')));
      await settleFrames(tester);
      expect(s.repo.starts.single.allowTranscript, isFalse);
    });

    testWidgets('choosing Speak starts a spoken conversation', (tester) async {
      final s = await pumpConversation(tester, width: 800, spoken: true);
      expect(s.repo.starts.single.mode, LiveInputMode.speech);
      expect(find.byKey(const Key('live-talk')), findsOneWidget);
      expect(find.text('Hold to talk'), findsOneWidget);
      expect(find.text('Tap to start, tap to stop'), findsOneWidget);
      expect(find.byKey(const Key('live-type-instead')), findsOneWidget);
      expect(find.byKey(const Key('live-input')), findsNothing);
    });

    testWidgets('a refusal to start is shown on the card', (tester) async {
      final repo = FakeLiveRepository()
        ..startFailure = const ApiException(
          'speech is not available right now; please choose typing',
          statusCode: 409,
        );
      await pumpLive(tester, width: 800, repo: repo);
      await tester.tap(find.byKey(const Key('live-mode-speech')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-begin')));
      await settleFrames(tester);
      expect(find.byKey(const Key('live-choice-error')), findsOneWidget);
      expect(find.text('speech is not available right now; please choose typing'),
          findsOneWidget);
      expect(find.byKey(const Key('live-choice')), findsOneWidget);
    });
  });

  group('the conversation', () {
    testWidgets('shows the looping muted avatar, the caption, the badge, the '
        'voice switch and the turns left, and speaks the opening',
        (tester) async {
      final s = await pumpConversation(tester);
      expect(find.byKey(const Key('live-avatar-stage')), findsOneWidget);
      final config = s.configs.last;
      expect(config.url, liveAvatarUrl, reason: 'resolved by the repository');
      expect(config.loop, isTrue);
      expect(config.muted, isTrue);
      expect(find.byKey(const Key('fake-video')), findsOneWidget);

      expect(captionText(tester), 'Hi Sam! What do you like most about trains?');
      expect(
        find.text("Development avatar - sample face and your browser's voice"),
        findsOneWidget,
      );
      expect(find.text('Voice on'), findsOneWidget);
      expect(find.text('4 turns left'), findsOneWidget);
      expect(find.byKey(const Key('live-end')), findsOneWidget);
      expect(find.byKey(const Key('live-input')), findsOneWidget);
      expect(find.text('0/400'), findsOneWidget);
      expect(find.text('Hold to talk'), findsNothing);
      expect(s.speech.spoken, ['Hi Sam! What do you like most about trains?']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no development badge for a real avatar', (tester) async {
      await pumpConversation(
        tester,
        repo: FakeLiveRepository(syntheticAvatar: false),
      );
      expect(find.byKey(const Key('live-synthetic-badge')), findsNothing);
    });

    testWidgets('Send puts the message in, clears the field, shows and speaks '
        'the reply and counts down', (tester) async {
      final s = await pumpConversation(tester);
      await tester.enterText(find.byKey(const Key('live-input')), 'I like steam');
      await tester.pump();
      expect(find.text('12/400'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-send')));
      await settleFrames(tester);

      expect(s.repo.typed.single.expectTurn, 0);
      expect(s.repo.typed.single.text, 'I like steam');
      expect(tester.widget<TextField>(find.byKey(const Key('live-input'))).controller!.text,
          isEmpty);
      expect(captionText(tester), 'Reply 1: tell me more about trains.');
      expect(find.text('You: I like steam'), findsOneWidget);
      expect(find.text('3 turns left'), findsOneWidget);
      expect(s.speech.spoken.last, 'Reply 1: tell me more about trains.');

      await typeAndSend(tester, 'And big ones');
      expect(s.repo.typed.last.expectTurn, 1);
      expect(find.text('2 turns left'), findsOneWidget);
    });

    testWidgets('Send is off for an empty message', (tester) async {
      await pumpConversation(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('live-send'))).onPressed,
          isNull);
      await tester.enterText(find.byKey(const Key('live-input')), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('live-send'))).onPressed,
          isNull);
    });

    testWidgets('Enter sends; Shift+Enter does not', (tester) async {
      final s = await pumpConversation(tester);
      await tester.enterText(find.byKey(const Key('live-input')), 'first line');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settleFrames(tester);
      expect(s.repo.typed, isEmpty, reason: 'Shift+Enter is a new line');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleFrames(tester);
      expect(s.repo.typed.single.text, 'first line');
    });

    testWidgets('the field and Send are off while a turn is in flight',
        (tester) async {
      final s = await pumpConversation(tester);
      final gate = s.repo.gate = Completer<void>();
      await tester.enterText(find.byKey(const Key('live-input')), 'one');
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-send')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('live-input'))).enabled,
          isFalse);
      expect(tester.widget<FilledButton>(find.byKey(const Key('live-send'))).onPressed,
          isNull);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('live-end'))).onPressed,
          isNull);
      expect(find.text('One moment...'), findsOneWidget);
      gate.complete();
      await settleFrames(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('live-input'))).enabled,
          isTrue);
      expect(s.repo.typed.length, 1);
    });

    testWidgets('Voice off keeps the lines silent, Voice on speaks them',
        (tester) async {
      final s = await pumpConversation(tester);
      expect(s.speech.spoken.length, 1);
      await tester.tap(find.byKey(const Key('live-voice-toggle')));
      await tester.pump();
      expect(find.text('Voice off'), findsOneWidget);
      await typeAndSend(tester, 'one');
      expect(s.speech.spoken.length, 1);
      expect(captionText(tester), startsWith('Reply 1'));
      await tester.tap(find.byKey(const Key('live-voice-toggle')));
      await tester.pump();
      expect(find.text('Voice on'), findsOneWidget);
      await typeAndSend(tester, 'two');
      expect(s.speech.spoken.last, startsWith('Reply 2'));
    });

    testWidgets('no voice switch where the browser cannot speak',
        (tester) async {
      await pumpConversation(
        tester,
        speech: FakeSpeechSynthesizer(available: false),
      );
      expect(find.byKey(const Key('live-voice-toggle')), findsNothing);
    });

    testWidgets('a 409 shows the server text with Reload, which carries on',
        (tester) async {
      final s = await pumpConversation(tester);
      s.repo.seedOpen(used: 1);
      await tester.enterText(find.byKey(const Key('live-input')), 'hello');
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-send')));
      await settleFrames(tester);

      expect(find.byKey(const Key('live-error')), findsOneWidget);
      expect(find.text('this turn was already sent; reload the conversation'),
          findsOneWidget);
      expect(find.text('Reload'), findsOneWidget);
      // The text stays in the field.
      expect(tester.widget<TextField>(find.byKey(const Key('live-input'))).controller!.text,
          'hello');

      await tester.tap(find.byKey(const Key('live-error-action')));
      await settleFrames(tester);
      expect(find.byKey(const Key('live-error')), findsNothing);
      expect(find.text('3 turns left'), findsOneWidget);
      expect(captionText(tester), 'Reply 1');
      await tester.tap(find.byKey(const Key('live-send')));
      await settleFrames(tester);
      expect(s.repo.typed.last.expectTurn, 1);
      expect(s.repo.typed.last.text, 'hello');
    });

    testWidgets('a 422 shows the server text with Try again', (tester) async {
      final s = await pumpConversation(tester);
      s.repo.turnFailures.add(const ApiException(
        'say or type something first',
        statusCode: 422,
      ));
      await typeAndSend(tester, 'hmm');
      expect(find.text('say or type something first'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Reload'), findsNothing);
      await tester.tap(find.byKey(const Key('live-error-action')));
      await tester.pump();
      expect(find.byKey(const Key('live-error')), findsNothing);
    });

    testWidgets('a distress signal shows a calm break offer; Keep talking '
        'hides it, Pause pauses the session', (tester) async {
      final s = await pumpConversation(tester);
      s.repo.distressOnNext = true;
      await typeAndSend(tester, 'I feel scared');
      expect(find.byKey(const Key('live-distress')), findsOneWidget);
      expect(find.text("It's okay to take a break."), findsOneWidget);
      expect(find.text('Pause'), findsWidgets);
      expect(find.text('Keep talking'), findsOneWidget);

      await tester.tap(find.byKey(const Key('live-distress-continue')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('live-distress')), findsNothing);
      expect(find.byKey(const Key('live-input')), findsOneWidget);
      // "Keep talking" gives the keyboard back to the message field.
      final field = tester.widget<TextField>(find.byKey(const Key('live-input')));
      expect(field.focusNode!.hasFocus, isTrue);

      s.repo.distressOnNext = true;
      await typeAndSend(tester, 'still scared');
      expect(find.byKey(const Key('live-distress')), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-distress-pause')));
      await settleReal(tester);
      expect(s.flow.phase, StepPhase.paused);
      expect(find.byKey(const Key('paused-panel')), findsOneWidget);
      expect(find.byKey(const Key('live-practice')), findsNothing);
    });

    testWidgets('pause keeps what was typed; resume brings the conversation '
        'back', (tester) async {
      final s = await pumpConversation(tester);
      await tester.enterText(find.byKey(const Key('live-input')), 'half a thou');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pause')));
      await settleReal(tester);
      expect(find.byKey(const Key('paused-panel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('resume-panel')));
      await settleReal(tester);
      expect(s.flow.phase, StepPhase.running);
      expect(find.byKey(const Key('live-practice')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('live-input'))).controller!.text,
          'half a thou');
      expect(captionText(tester), 'Hi Sam! What do you like most about trains?');
    });

    testWidgets('End conversation shows the closing line, stops the input and '
        'Continue goes on to the post observation', (tester) async {
      final s = await pumpConversation(tester);
      await typeAndSend(tester, 'hello');
      await tester.tap(find.byKey(const Key('live-end')));
      await settleFrames(tester);

      expect(s.repo.endCalls, 1);
      expect(captionText(tester), 'Thank you for talking with me about trains.');
      expect(find.byKey(const Key('live-ended')), findsOneWidget);
      expect(find.text('You ended the conversation'), findsOneWidget);
      expect(find.byKey(const Key('live-input')), findsNothing);
      expect(find.byKey(const Key('live-send')), findsNothing);
      expect(find.byKey(const Key('live-end')), findsNothing);
      expect(s.speech.spoken.last, 'Thank you for talking with me about trains.');
      expect(s.flow.step, SessionStep.practice);

      await tester.tap(find.byKey(const Key('live-continue')));
      await settleReal(tester);
      expect(s.flow.step, SessionStep.post);
      expect(find.byKey(const Key('post-start')), findsOneWidget);
      expect(
        find.text('You will see the avatar one more time. Just look at it '
            'naturally. There is nothing to do and nothing will be asked.'),
        findsOneWidget,
      );
    });

    testWidgets('the last allowed turn ends it by itself, with the closing '
        'line', (tester) async {
      await pumpConversation(tester, repo: FakeLiveRepository(maxTurns: 1));
      await typeAndSend(tester, 'only one');
      expect(find.byKey(const Key('live-ended')), findsOneWidget);
      expect(find.text('All the turns were used'), findsOneWidget);
      expect(find.byKey(const Key('live-input')), findsNothing);
      expect(find.byKey(const Key('live-continue')), findsOneWidget);
    });

    testWidgets('the post observation shows only the avatar, then the comfort '
        'question', (tester) async {
      final s = await pumpConversation(
        tester,
        repo: FakeLiveRepository(maxTurns: 1),
        postSeconds: 2,
      );
      await typeAndSend(tester, 'only one');
      await tester.tap(find.byKey(const Key('live-continue')));
      await settleReal(tester);
      await tester.tap(find.byKey(const Key('post-start')));
      await settleReal(tester);

      expect(s.flow.phase, StepPhase.running);
      expect(find.byKey(const Key('live-avatar-stage')), findsOneWidget);
      expect(find.byKey(const Key('live-caption')), findsNothing);
      expect(find.byKey(const Key('live-input')), findsNothing);
      expect(find.byKey(const Key('live-voice-toggle')), findsNothing);
      expect(s.rig.repo.layouts.last.segment, SessionSegmentName.post);

      await tester.pump(const Duration(seconds: 3));
      await settleReal(tester);
      expect(s.flow.askingComfort, isTrue);
      expect(find.byKey(const Key('comfort-question')), findsOneWidget);
    });
  });

  group('speech mode', () {
    testWidgets('hold to talk: pressing records, letting go after holding '
        'uploads with expect_turn and shows what was heard', (tester) async {
      final s = await pumpConversation(tester, spoken: true);
      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(const Key('live-talk'))));
      await tester.pump();
      expect(s.mic.startCount, 1);
      expect(s.live.recording, isTrue);
      expect(find.text('Listening... release to send'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await settleFrames(tester);

      expect(s.mic.stopCount, 1);
      final sent = s.repo.audio.single;
      expect(sent.expectTurn, 0);
      expect(sent.clip.bytes, [1, 2, 3, 4]);
      expect(sent.clip.contentType, 'audio/webm;codecs=opus');
      expect(s.repo.typed, isEmpty);
      expect(find.text('You: I like steam trains'), findsOneWidget);
      expect(captionText(tester), startsWith('Reply 1'));
      expect(find.text('3 turns left'), findsOneWidget);
      expect(find.text('Hold to talk'), findsOneWidget);
    });

    testWidgets('tap to start, tap to stop also works', (tester) async {
      final s = await pumpConversation(tester, spoken: true);
      await tester.tap(find.byKey(const Key('live-talk')));
      await settleFrames(tester);
      expect(s.live.recording, isTrue, reason: 'a short tap keeps recording');
      expect(s.repo.audio, isEmpty);
      expect(find.text('Release or tap to send'), findsOneWidget);

      await tester.tap(find.byKey(const Key('live-talk')));
      await settleFrames(tester);
      expect(s.live.recording, isFalse);
      expect(s.repo.audio.length, 1);
      expect(s.repo.audio.single.expectTurn, 0);
    });

    testWidgets('the keyboard works the button too (Space starts and stops)',
        (tester) async {
      final s = await pumpConversation(tester, spoken: true);
      Focus.of(tester.element(find.byKey(const Key('live-talk')))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleFrames(tester);
      expect(s.live.recording, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleFrames(tester);
      expect(s.repo.audio.length, 1);
    });

    testWidgets('Type instead shows the text field in a spoken conversation; '
        'Speak instead brings the button back', (tester) async {
      final s = await pumpConversation(tester, spoken: true);
      await tester.tap(find.byKey(const Key('live-type-instead')));
      await tester.pump();
      expect(find.byKey(const Key('live-input')), findsOneWidget);
      expect(find.byKey(const Key('live-talk')), findsNothing);
      await typeAndSend(tester, 'typed instead');
      expect(s.repo.typed.single.text, 'typed instead');
      expect(s.repo.audio, isEmpty);

      await tester.tap(find.byKey(const Key('live-speak-instead')));
      await tester.pump();
      expect(find.byKey(const Key('live-talk')), findsOneWidget);
    });

    testWidgets('a blocked microphone shows its message and offers typing',
        (tester) async {
      final mic = FakeAudioRecorder()
        ..startError = const AudioRecorderException(
            'Microphone access was not allowed. Allow it, or type instead.');
      await pumpConversation(tester, spoken: true, mic: mic);
      await tester.tap(find.byKey(const Key('live-talk')));
      await settleFrames(tester);
      expect(find.text('Microphone access was not allowed. Allow it, or type instead.'),
          findsOneWidget);
      expect(find.byKey(const Key('live-input')), findsOneWidget);
    });

    testWidgets('a refused spoken turn shows the server text and can be '
        'tried again', (tester) async {
      final s = await pumpConversation(tester, spoken: true);
      s.repo.turnFailures.add(const ApiException(
        'we could not turn that into text (empty); please try again or type',
        statusCode: 422,
      ));
      await tester.tap(find.byKey(const Key('live-talk')));
      await settleFrames(tester);
      await tester.tap(find.byKey(const Key('live-talk')));
      await settleFrames(tester);
      expect(
        find.text('we could not turn that into text (empty); please try again '
            'or type'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-error-action')));
      await tester.pump();
      expect(find.byKey(const Key('live-talk')), findsOneWidget);
    });
  });

  group('the gaze layout', () {
    testWidgets('the regions posted for the practice come from face_layout and '
        'the rectangle the video is drawn in', (tester) async {
      final s = await pumpConversation(tester, width: 1440, height: 900);
      final posted =
          s.rig.repo.layouts.where((l) => l.segment == SessionSegmentName.practice);
      expect(posted, isNotEmpty);
      final layout = posted.last.layout;

      final stage = tester.getRect(find.byKey(const Key('live-avatar-stage')));
      final drawn = containedVideoRect(
        Box(stage.left, stage.top, stage.width, stage.height),
        1920,
        1080,
      );
      expectBox(
        layout.faceBox,
        Box(drawn.x + 0.3 * drawn.w, drawn.y + 0.1 * drawn.h, 0.4 * drawn.w,
            0.8 * drawn.h),
      );
      expectBox(
        layout.eyeRegion,
        Box(drawn.x + 0.3 * drawn.w, drawn.y + 0.25 * drawn.h, 0.4 * drawn.w,
            0.2 * drawn.h),
      );
      expectBox(
        layout.mouthRegion,
        Box(drawn.x + 0.3 * drawn.w, drawn.y + 0.55 * drawn.h, 0.4 * drawn.w,
            0.25 * drawn.h),
      );
      expect(layout.screen, const ScreenInfo(w: 1440, h: 900));
      expect(layout.eyeRegion.bottom, lessThanOrEqualTo(layout.mouthRegion.y),
          reason: 'the eyes are above the mouth');
      expect(s.rig.repo.eventTypes.where((t) => t == SessionEventType.segmentStart),
          hasLength(2), reason: 'baseline and practice');
    });

    testWidgets('a protocol without a face layout records no practice segment',
        (tester) async {
      final s = await pumpConversation(
        tester,
        repo: FakeLiveRepository()..faceLayout = null,
      );
      expect(s.rig.repo.layouts.where((l) => l.segment == SessionSegmentName.practice),
          isEmpty);
      expect(find.byKey(const Key('live-input')), findsOneWidget,
          reason: 'the conversation itself still runs');
    });

    testWidgets('a video that fails shows a message and a retry; the '
        'conversation goes on', (tester) async {
      final s = await pumpConversation(tester);
      s.configs.last.onError?.call('x');
      await settleFrames(tester);
      expect(find.byKey(const Key('live-video-problem')), findsOneWidget);
      expect(find.byKey(const Key('live-input')), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-video-retry')));
      await settleFrames(tester);
      expect(find.byKey(const Key('live-video-problem')), findsNothing);
      expect(find.byKey(const Key('fake-video')), findsOneWidget);
    });
  });

  group('the session around it', () {
    testWidgets('the instructions say it is a chat with the topic',
        (tester) async {
      useWindow(tester, 800, 900);
      final rig = protocolRig(
        liveProtocol(baselineSeconds: 0.3),
        timing: widgetTiming,
        screen: const ScreenInfo(w: 800, h: 900),
      );
      addTearDown(rig.dispose);
      await tester.runAsync(() => rig.toPractice());
      await tester.pumpWidget(AppScope(
        dependencies: TestBed().dependencies,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: SessionFlowScreen(controller: rig.controller),
        ),
      ));
      await tester.pump();
      expect(
        find.textContaining('You will have a short chat with a virtual avatar '
            'about trains.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('practice-start')), findsOneWidget);
    });

    testWidgets('the introduction lists the chat', (tester) async {
      useWindow(tester, 800, 1400);
      final rig = protocolRig(liveProtocol(), timing: widgetTiming);
      addTearDown(rig.dispose);
      await tester.runAsync(rig.controller.loadIntro);
      await tester.pumpWidget(AppScope(
        dependencies: TestBed().dependencies,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: SessionFlowScreen(controller: rig.controller),
        ),
      ));
      await tester.pump();
      expect(
        find.textContaining(
          'You have a short chat with a virtual avatar, typing or speaking.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });
  });

  group('confirm my topic for a live conversation', () {
    Assignment pendingLive() => const Assignment(
          id: '1',
          status: AssignmentStatus.pendingTopic,
          protocol: ProtocolRef(
            id: '1',
            name: 'Live chat',
            path: ProtocolPath.liveConversation,
          ),
        );

    testWidgets('says the avatar will chat, and after saving says it is ready '
        'to start, not waiting for content', (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [pendingLive()]),
      );
      await tester.pumpWidget(AppScope(
        dependencies: bed.dependencies,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TopicScreen(assignment: pendingLive()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('chat about it with a virtual avatar'),
          findsOneWidget);
      await tester.enterText(find.byKey(const Key('topic-field')), 'trains');
      await tester.pump();
      await tester.tap(find.byKey(const Key('topic-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('topic-submitted')), findsOneWidget);
      expect(find.byKey(const Key('topic-ready-note')), findsOneWidget);
      expect(find.text('Your conversation is ready.'), findsOneWidget);
      expect(find.byKey(const Key('content-pending-note')), findsNothing);
      expect(find.text('Content being prepared by your researcher'), findsNothing);
    });

    testWidgets('home offers Prepare for session for the ready live '
        'assignment', (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [
          Assignment(
            id: '1',
            status: AssignmentStatus.ready,
            protocol: const ProtocolRef(
              id: '1',
              name: 'Live chat',
              path: ProtocolPath.liveConversation,
            ),
            topic: 'trains',
          ),
        ]),
      );
      await pumpApp(tester, bed);
      expect(find.byKey(const Key('prepare-1')), findsOneWidget);
      expect(find.text('Topic: trains'), findsOneWidget);
    });
  });

  group('the summary', () {
    Future<SessionFlowController> summaryFor(
      WidgetTester tester, {
      required SessionOutcomes outcomes,
    }) async {
      final rig = protocolRig(liveProtocol(baselineSeconds: 0.3),
          timing: widgetTiming);
      addTearDown(rig.dispose);
      rig.repo.outcomes = outcomes;
      await tester.runAsync(() async {
        await rig.toCameraCheck();
        await rig.controller.endEarly();
      });
      return rig.controller;
    }

    Future<void> pumpSummary(WidgetTester tester, SessionFlowController c) async {
      await tester.pumpWidget(AppScope(
        dependencies: TestBed().dependencies,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: SessionFlowScreen(key: ValueKey(c), controller: c),
        ),
      ));
      await tester.pump();
    }

    const held = SessionOutcomes(
      gaze: GazeOutcome(reason: 'synthetic_estimator'),
      comfort: ComfortOutcome(answers: 2, min: 4, mean: 4.5),
      conversation: ConversationOutcome(
        participantTurns: 4,
        avatarTurns: 5,
        onTopic: 3,
        onTopicShare: 0.75,
        redirects: 1,
        endReason: 'turn_limit',
        note: 'On-topic judgements come from the reply model.',
      ),
      improvement: ImprovementOutcome(
        eligible: true,
        result: true,
        eyeShareUp: true,
        comfortNotWorse: true,
        comprehensionMaintained: true,
      ),
    );

    testWidgets('shows the conversation next to gaze and comfort: messages, '
        'on-topic share with who judged it, and how it ended', (tester) async {
      useWindow(tester, 1440, 1000);
      final c = await summaryFor(tester, outcomes: held);
      await pumpSummary(tester, c);

      expect(find.byKey(const Key('outcome-conversation')), findsOneWidget);
      expect(find.byKey(const Key('outcome-comprehension')), findsNothing);
      expect(find.byKey(const Key('outcome-number-task')), findsNothing);
      expect(find.text('Conversation'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('conversation-turns'))).data, '4');
      expect(tester.widget<Text>(find.byKey(const Key('conversation-on-topic'))).data,
          '75 %');
      expect(tester.widget<Text>(find.byKey(const Key('conversation-end'))).data,
          'All the turns were used');
      expect(
        find.textContaining('judged by the reply model'),
        findsOneWidget,
      );
      // Beside the other outcomes on a wide screen.
      final gaze = tester.getTopLeft(find.byKey(const Key('outcome-gaze')));
      final conversation =
          tester.getTopLeft(find.byKey(const Key('outcome-conversation')));
      final comfort = tester.getTopLeft(find.byKey(const Key('outcome-comfort')));
      expect(conversation.dy, gaze.dy);
      expect(comfort.dy, gaze.dy);
      expect(conversation.dx, greaterThan(gaze.dx));
      expect(comfort.dx, greaterThan(conversation.dx));
      expect(find.text('The conversation held'), findsOneWidget);
      expect(find.text('Understanding was kept'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says "Not judged" when nothing was judged, and "None sent" '
        'when the participant wrote nothing', (tester) async {
      useWindow(tester, 800, 1400);
      final c = await summaryFor(
        tester,
        outcomes: const SessionOutcomes(
          conversation: ConversationOutcome(
            participantTurns: 2,
            avatarTurns: 3,
            endReason: 'participant_ended',
          ),
        ),
      );
      await pumpSummary(tester, c);
      expect(tester.widget<Text>(find.byKey(const Key('conversation-on-topic'))).data,
          'Not judged');
      expect(find.text('You ended the conversation'), findsOneWidget);

      final none = await summaryFor(
        tester,
        outcomes: const SessionOutcomes(
          conversation: ConversationOutcome(endReason: 'session_ended'),
        ),
      );
      await pumpSummary(tester, none);
      expect(find.text('None sent'), findsOneWidget);
      expect(find.byKey(const Key('conversation-on-topic')), findsNothing);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('fits ${width.toInt()} px', (tester) async {
        useWindow(tester, width, width == 360 ? 640 : 900);
        final c = await summaryFor(tester, outcomes: held);
        await pumpSummary(tester, c);
        expect(find.byKey(const Key('outcome-conversation')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('layout without overflow', () {
    for (final width in [360.0, 800.0, 1440.0]) {
      final height = width == 360 ? 640.0 : 900.0;

      testWidgets('the choice card at ${width.toInt()} px', (tester) async {
        await pumpLive(
          tester,
          width: width,
          height: height,
          repo: FakeLiveRepository(storeTranscriptOffered: true),
        );
        expect(find.byKey(const Key('live-begin')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a typed conversation with every banner showing, at '
          '${width.toInt()} px', (tester) async {
        final repo = FakeLiveRepository(
          openingLine: 'Hi Sam! I would love to hear about trains. What is the '
              'thing you like most about them, and why do you think that is '
              'the case for you?',
        );
        final s = await pumpConversation(tester,
            width: width, height: height, repo: repo);
        // A long message in the field, a distress offer and an error at once.
        repo.distressOnNext = true;
        await typeAndSend(tester, 'I feel a bit scared');
        repo.turnFailures.add(const ApiException(
          'this turn was already sent; reload the conversation',
          statusCode: 409,
        ));
        await tester.enterText(
          find.byKey(const Key('live-input')),
          'a long message that wraps over several lines ' * 4,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('live-send')));
        await settleFrames(tester);

        expect(find.byKey(const Key('live-distress')), findsOneWidget);
        expect(find.byKey(const Key('live-error')), findsOneWidget);
        expect(tester.takeException(), isNull);
        // The stage keeps a usable size and the input stays on the screen.
        final stage = tester.getRect(find.byKey(const Key('live-avatar-stage')));
        expect(stage.height, greaterThanOrEqualTo(150));
        expect(stage.width, greaterThanOrEqualTo(width >= 900 ? 600 : 300));
        final input = tester.getRect(find.byKey(const Key('live-input')));
        expect(input.bottom, lessThanOrEqualTo(height));
        expect(input.left, greaterThanOrEqualTo(0));
        expect(input.right, lessThanOrEqualTo(width));
        expect(s.live.phase, LivePhase.conversation);
      });

      testWidgets('a spoken conversation at ${width.toInt()} px',
          (tester) async {
        await pumpConversation(tester,
            width: width, height: height, spoken: true);
        expect(find.byKey(const Key('live-talk')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final talk = tester.getRect(find.byKey(const Key('live-talk')));
        expect(talk.bottom, lessThanOrEqualTo(height));
        expect(talk.width, greaterThan(100));
      });

      testWidgets('the ended conversation at ${width.toInt()} px',
          (tester) async {
        await pumpConversation(tester,
            width: width, height: height, repo: FakeLiveRepository(maxTurns: 1));
        await typeAndSend(tester, 'bye');
        expect(find.byKey(const Key('live-continue')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('on a wide window the panel sits beside the video; on a '
        'narrow one below it', (tester) async {
      await pumpConversation(tester, width: 1440, height: 900);
      final wideStage = tester.getRect(find.byKey(const Key('live-avatar-stage')));
      final wideCaption = tester.getRect(find.byKey(const Key('live-caption')));
      expect(wideCaption.left, greaterThanOrEqualTo(wideStage.right));

      await pumpConversation(tester, width: 360, height: 640);
      final stage = tester.getRect(find.byKey(const Key('live-avatar-stage')));
      final caption = tester.getRect(find.byKey(const Key('live-caption')));
      expect(caption.top, greaterThanOrEqualTo(stage.bottom));
    });
  });
}

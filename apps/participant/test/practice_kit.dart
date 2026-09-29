import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:participant_app/features/session/application/gradual_practice_controller.dart';
import 'package:participant_app/features/session/application/interest_practice_controller.dart';
import 'package:participant_app/features/session/application/segment_recorder.dart';
import 'package:participant_app/features/session/domain/session_step.dart';
import 'package:participant_app/features/session/domain/stimulus_geometry.dart';

import 'fakes.dart';
import 'session_kit.dart';

/// Records what a practice controller asks of the session flow.
class FakeSegmentRecorder implements SegmentRecorder {
  final List<String> calls = [];
  final List<({SessionSegmentName segment, StimulusLayout layout, int? stage})>
      opened = [];
  final List<({SessionSegmentName segment, StimulusLayout layout})> updated = [];
  final List<SessionSegmentName> closed = [];
  int _now = 1000;
  Object? openFailure;

  @override
  int get nowMs => _now += 25;

  @override
  Future<void> openSegment(
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  }) async {
    if (openFailure != null) throw openFailure!;
    calls.add('open:${segment.wire}${stageIndex == null ? '' : ':$stageIndex'}');
    opened.add((segment: segment, layout: layout, stage: stageIndex));
  }

  @override
  Future<void> updateLayout(
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  }) async {
    calls.add('update:${segment.wire}');
    updated.add((segment: segment, layout: layout));
  }

  @override
  Future<void> closeSegment(SessionSegmentName segment) async {
    calls.add('close:${segment.wire}');
    closed.add(segment);
  }
}

/// Timing that makes the practice run in a fraction of a second.
const practiceTiming = SessionTiming(
  countdownStep: Duration(milliseconds: 2),
  settle: Duration(milliseconds: 8),
  calibrationCapture: Duration(milliseconds: 40),
  validationCapture: Duration(milliseconds: 40),
  baseline: Duration(milliseconds: 300),
  progressTick: Duration(milliseconds: 10),
  secondsUnit: Duration(milliseconds: 10),
  leadIn: Duration(milliseconds: 2),
  interTrial: Duration(milliseconds: 2),
);

ProtocolDefinition gradualProtocol({
  List<GradualStage>? stages,
  bool askEveryStage = true,
  double baselineSeconds = 30,
  double postSeconds = 30,
}) =>
    ProtocolDefinition(
      path: ProtocolPath.gradualFace,
      baselineSeconds: baselineSeconds,
      postSeconds: postSeconds,
      comfort: ComfortConfig(askEveryStage: askEveryStage),
      gradual: GradualConfig(
        stages: stages ??
            const [
              GradualStage(trials: 2, trialSeconds: 50),
              GradualStage(
                numberZone: NumberZone.faceEdge,
                trials: 2,
                trialSeconds: 50,
              ),
              GradualStage(
                faceLevel: 1,
                numberZone: NumberZone.faceEdge,
                trials: 2,
                trialSeconds: 50,
              ),
            ],
      ),
    );

ProtocolDefinition interestProtocol({
  double baselineSeconds = 30,
  double postSeconds = 30,
}) =>
    ProtocolDefinition(
      path: ProtocolPath.interestConversation,
      baselineSeconds: baselineSeconds,
      postSeconds: postSeconds,
      interest: const InterestConfig(),
    );

const testFaceLayout = NormalizedFaceLayout(
  faceBox: Box(0.3, 0.1, 0.4, 0.8),
  eyeRegion: Box(0.3, 0.25, 0.4, 0.2),
  mouthRegion: Box(0.3, 0.55, 0.4, 0.25),
);

PersonalizedContent sampleContent({String suffix = ''}) => PersonalizedContent(
      title: 'Trains',
      startSegment: 's1',
      postSegment: 's3',
      segments: [
        PersonalizedSegment(
          id: 's1',
          text: 'Hi Sam, today we talk about trains.',
          mediaUrl: '/media/s1$suffix',
          durationS: 20,
          faceLayout: testFaceLayout,
          question: const PersonalizedQuestion(
            id: 'q1',
            prompt: 'Which do you prefer?',
            options: ['Trains', 'Planes'],
          ),
        ),
        PersonalizedSegment(
          id: 's2',
          text: 'Trains are great.',
          mediaUrl: '/media/s2$suffix',
          durationS: 15,
          faceLayout: testFaceLayout,
        ),
        PersonalizedSegment(
          id: 's2b',
          text: 'Planes are great.',
          mediaUrl: '/media/s2b$suffix',
          durationS: 15,
          faceLayout: testFaceLayout,
        ),
        PersonalizedSegment(
          id: 's3',
          text: 'Thank you.',
          mediaUrl: '/media/s3$suffix',
          durationS: 10,
          faceLayout: testFaceLayout,
        ),
      ],
      comprehension: const [
        PersonalizedQuestion(
          id: 'c1',
          prompt: 'What colour was the train?',
          options: ['Red', 'Blue', 'Green'],
        ),
        PersonalizedQuestion(
          id: 'c2',
          prompt: 'Where did it go?',
          options: ['Paris', 'Rome'],
        ),
      ],
    );

const screen1440 = ScreenInfo(w: 1440, h: 900);

/// The face card layout the flow would use on [screen].
StimulusLayout faceLayoutFor(ScreenInfo screen, {double bottomInset = 168}) =>
    buildFaceLayout(screen: screen, residualPx: 60, bottomInset: bottomInset)
        .layout;

/// Everything a gradual controller test needs.
class GradualRig {
  GradualRig({
    ProtocolDefinition? protocol,
    ResponseMode profileMode = ResponseMode.keyboard,
    int seed = 1,
    ScreenInfo screen = screen1440,
  })  : repo = FakeSessionRepository(),
        recorder = FakeSegmentRecorder() {
    controller = GradualPracticeController(
      sessionId: '11',
      protocol: protocol ?? gradualProtocol(),
      layout: faceLayoutFor(screen),
      repository: repo,
      recorder: recorder,
      profileMode: profileMode,
      timing: practiceTiming,
      random: math.Random(seed),
      onFinished: finished.add,
    );
  }

  final FakeSessionRepository repo;
  final FakeSegmentRecorder recorder;
  late final GradualPracticeController controller;
  final List<PracticeEnd> finished = [];

  /// Answers every trial of the stage that is running with [answer] (the
  /// shown value by default) until the stage is over.
  Future<void> playStage({String? Function(String shown)? answer}) async {
    final g = controller;
    while (true) {
      await until(
        () =>
            g.phase == GradualPhase.trial ||
            g.phase == GradualPhase.comfort ||
            g.phase == GradualPhase.decision ||
            g.phase == GradualPhase.problem ||
            g.phase == GradualPhase.finished,
        what: 'a trial or the end of the stage',
      );
      if (g.phase != GradualPhase.trial) return;
      final current = g.stimulus!;
      final shown = current.shown;
      g.submit(answer == null ? shown : (answer(shown) ?? shown));
      // Wait for the answer to be taken (the next number may already be
      // showing by the time we look).
      await until(
        () => g.phase != GradualPhase.trial || !identical(g.stimulus, current),
        what: 'trial to close',
      );
    }
  }
}

/// Everything an interest controller test needs.
class InterestRig {
  InterestRig({
    PersonalizedContent? content,
    bool showCaptions = false,
    ScreenInfo screen = screen1440,
  })  : repo = FakeSessionRepository(),
        recorder = FakeSegmentRecorder(),
        content = content ?? sampleContent() {
    repo.answerResult = (a) {
      if (a.kind == AnswerKind.comprehension) {
        return AnswerResult(correct: a.option == 'Red');
      }
      final next = {'Trains': 's2', 'Planes': 's2b'}[a.option];
      return AnswerResult(nextSegmentId: next);
    };
    controller = InterestPracticeController(
      sessionId: '11',
      content: this.content,
      reloadContent: () async {
        reloads++;
        return sampleContent(suffix: '-fresh');
      },
      repository: repo,
      recorder: recorder,
      screen: () => screen,
      showCaptions: showCaptions,
      onFinished: finished.add,
      onPostFinished: () => postFinished++,
    );
  }

  final FakeSessionRepository repo;
  final FakeSegmentRecorder recorder;
  final PersonalizedContent content;
  late final InterestPracticeController controller;
  final List<PracticeEnd> finished = [];
  int postFinished = 0;
  int reloads = 0;

  /// The player reports that the current video started, is drawn in
  /// [rect], then plays to its end.
  Future<void> playCurrent({Box rect = const Box(0, 40, 1440, 860)}) async {
    controller.onVideoRect(rect);
    controller.onVideoPlaying();
    await settle();
    await controller.onVideoEnded();
  }
}

/// Assignment for a protocol of [path].
Assignment assignmentFor(
  ProtocolPath path, {
  String status = AssignmentStatus.ready,
  String? topic,
}) =>
    Assignment(
      id: '5',
      status: status,
      protocol: ProtocolRef(id: '7', name: 'Test protocol', version: 1, path: path),
      topic: topic ?? (path == ProtocolPath.interestConversation ? 'trains' : null),
    );

/// The flow controller of a protocol session, with the fakes it needs.
Rig protocolRig(
  ProtocolDefinition protocol, {
  Profile profile = const Profile(displayName: 'Sam'),
  PersonalizedContent? content,
  SessionTiming timing = practiceTiming,
  ScreenInfo screen = screen1440,
  bool autoFrames = true,
}) {
  final rig = Rig(
    timing: timing,
    screen: screen,
    autoFrames: autoFrames,
    assignment: assignmentFor(protocol.path),
    assignments: FakeAssignmentsRepository(content: content),
    profile: FakeProfileRepository()..profile = profile,
    seed: 3,
  );
  rig.repo.protocolForCreate = ProtocolRef(
    id: '7',
    name: 'Test protocol',
    version: 1,
    path: protocol.path,
    definition: protocol,
  );
  return rig;
}

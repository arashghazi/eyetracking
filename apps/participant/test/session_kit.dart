import 'dart:async';
import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:participant_app/features/assignments/domain/assignments_repository.dart';
import 'package:participant_app/features/profile/domain/profile_repository.dart';
import 'package:participant_app/features/session/domain/live_repository.dart';
import 'package:participant_app/features/session/application/session_flow_controller.dart';
import 'package:participant_app/features/session/domain/session_repository.dart';
import 'package:participant_app/features/session/domain/session_step.dart';

/// One event the fake server received.
class RecordedEvent {
  const RecordedEvent(this.type, this.tMs, this.payload);

  final SessionEventType type;
  final int tMs;
  final Map<String, dynamic>? payload;
}

const acceptedCalibration = CalibrationResult(
  calibrationId: '1',
  residualPxMedian: 60,
  residualPxP90: 110,
  accepted: true,
);

const passedValidation = ValidationResult(
  validationId: '1',
  passed: true,
  correctRatio: 0.9,
  uncertainRatio: 0.05,
  sizeRatio: 3.1,
  targets: [
    ValidationTargetResult(
        region: 'eye', x: 1, y: 1, n: 10, majority: 'eye', correct: true),
  ],
);

const failedValidation = ValidationResult(
  validationId: '2',
  passed: false,
  correctRatio: 0.4,
  uncertainRatio: 0.3,
  sizeRatio: 1.2,
  reasons: [
    'Only 40 % of the dots were on target (80 % needed).',
    'Too many samples were uncertain.',
  ],
  targets: [
    ValidationTargetResult(
      region: 'eye',
      x: 1,
      y: 1,
      n: 10,
      majority: 'face_other',
      correct: false,
      uncertainShare: 0.3,
    ),
    ValidationTargetResult(
      region: 'outside',
      x: 5,
      y: 5,
      n: 10,
      majority: 'outside',
      correct: true,
    ),
  ],
);

/// In-memory stand-in for the research server's session endpoints.
class FakeSessionRepository implements SessionRepository {
  MeasurementSettings settings = MeasurementSettings.defaults;
  ApiException? createFailure;

  /// Thrown by every event post when set.
  ApiException? eventFailure;
  Readiness readinessValue = const Readiness(
    ready: false,
    reasons: [
      ReadinessReason.consentMissingOrOutdated,
      ReadinessReason.demographicsIncomplete,
    ],
  );
  CalibrationResult calibrationResult = acceptedCalibration;
  ValidationResult validationResult = passedValidation;
  bool syntheticSummary = false;
  List<SessionSummary> mineList = const [];

  final List<String> calls = [];
  final List<SessionCreateRequest> created = [];
  final List<CameraCheckRequest> cameraChecks = [];
  final List<List<CalibrationTargetCapture>> calibrations = [];
  final List<({StimulusLayout layout, List<ValidationTargetCapture> targets})>
      validations = [];
  final List<({SessionSegmentName segment, StimulusLayout layout, int? stageIndex})>
      layouts = [];
  final List<List<RawGazeSample>> sampleBatches = [];
  final List<RecordedEvent> events = [];
  int summaryCalls = 0;

  // Step 3.
  /// The protocol the created session carries (with its definition).
  ProtocolRef? protocolForCreate;
  SessionOutcomes? outcomes;
  List<StageRecord> stageRecords = const [];
  final List<List<TrialRecord>> trialBatches = [];
  final List<({int stageIndex, int? comfort})> stageRequests = [];
  final List<AnswerRequest> answers = [];

  /// Decisions handed out in order; when empty, [decide] answers.
  final List<StageDecision> scriptedDecisions = [];
  StageDecision Function(int stageIndex, int? comfort) decide =
      (stage, comfort) => StageDecision(
            kind: StageDecisionKind.advance,
            nextStageIndex: stage + 1,
            reason: 'criteria_met',
            correctRatio: 1,
            invalidShare: 0,
          );
  AnswerResult Function(AnswerRequest) answerResult =
      (a) => const AnswerResult();
  ApiException? trialsFailure;

  int get sampleCount => sampleBatches.fold(0, (a, b) => a + b.length);
  List<SessionEventType> get eventTypes => [for (final e in events) e.type];

  SessionSummary _summary(String status) => SessionSummary(
        id: '11',
        status: status,
        createdAt: '2026-09-29T08:00:00',
        synthetic: syntheticSummary,
        protocol: protocolForCreate,
      );

  @override
  Future<MeasurementSettings> measurementSettings() async => settings;

  @override
  Future<Readiness> readiness() async => readinessValue;

  @override
  Future<SessionSummary> create(SessionCreateRequest request) async {
    calls.add('create');
    if (createFailure != null) throw createFailure!;
    created.add(request);
    return _summary(SessionStatus.created);
  }

  @override
  Future<SessionSummary> cameraCheck(
    String sessionId,
    CameraCheckRequest body,
  ) async {
    calls.add('camera-check');
    cameraChecks.add(body);
    return _summary(
        body.faceDetected ? SessionStatus.cameraOk : SessionStatus.created);
  }

  @override
  Future<CalibrationResult> calibrate(
    String sessionId,
    List<CalibrationTargetCapture> targets,
  ) async {
    calls.add('calibration');
    calibrations.add(targets);
    return calibrationResult;
  }

  @override
  Future<ValidationResult> validate(
    String sessionId,
    StimulusLayout layout,
    List<ValidationTargetCapture> targets,
  ) async {
    calls.add('validation');
    validations.add((layout: layout, targets: targets));
    return validationResult;
  }

  @override
  Future<void> postLayout(
    String sessionId,
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  }) async {
    calls.add('layout:${segment.wire}');
    layouts.add((segment: segment, layout: layout, stageIndex: stageIndex));
  }

  @override
  Future<SampleAck> postSamples(
    String sessionId,
    List<RawGazeSample> samples,
  ) async {
    calls.add('samples');
    sampleBatches.add(samples);
    return SampleAck(stored: samples.length, invalid: 0);
  }

  @override
  Future<SessionSummary> postEvent(
    String sessionId,
    SessionEventType type, {
    required int tMs,
    Map<String, dynamic>? payload,
  }) async {
    calls.add('event:${type.wire}');
    if (eventFailure != null) throw eventFailure!;
    events.add(RecordedEvent(type, tMs, payload));
    return _summary(SessionStatus.running);
  }

  @override
  Future<SessionSummary> summary(String sessionId) async {
    summaryCalls++;
    return SessionSummary(
      id: '11',
      status: SessionStatus.ended,
      createdAt: '2026-09-29T08:00:00',
      endedAt: '2026-09-29T08:04:00',
      synthetic: syntheticSummary,
      coverage: const Coverage(
        totalMs: 30000,
        classifiableMs: 21000,
        uncertainMs: 6000,
        missingMs: 3000,
      ),
      faceRegionShare: 0.72,
      eyeRegionAttention: const EyeRegionAttention(
        evaluable: false,
        reason: 'Regional validation did not pass.',
      ),
      protocol: protocolForCreate,
      outcomes: outcomes,
      stages: stageRecords,
    );
  }

  @override
  Future<TrialAck> postTrials(
    String sessionId,
    List<TrialRecord> trials,
  ) async {
    calls.add('trials');
    if (trialsFailure != null) throw trialsFailure!;
    trialBatches.add(trials);
    return TrialAck(stored: trials.length, correct: 0);
  }

  @override
  Future<StageDecision> stageResult(
    String sessionId,
    int stageIndex, {
    int? comfortValue,
  }) async {
    calls.add('stage-result');
    stageRequests.add((stageIndex: stageIndex, comfort: comfortValue));
    if (scriptedDecisions.isNotEmpty) return scriptedDecisions.removeAt(0);
    return decide(stageIndex, comfortValue);
  }

  @override
  Future<AnswerResult> postAnswer(
    String sessionId,
    AnswerRequest answer,
  ) async {
    calls.add('answer:${answer.kind}');
    answers.add(answer);
    return answerResult(answer);
  }

  @override
  Future<List<SessionSummary>> mine() async => mineList;
}

/// Small timings so the flow runs in a fraction of a second.
const fastTiming = SessionTiming(
  countdownStep: Duration(milliseconds: 2),
  settle: Duration(milliseconds: 8),
  calibrationCapture: Duration(milliseconds: 40),
  validationCapture: Duration(milliseconds: 40),
  baseline: Duration(milliseconds: 300),
  progressTick: Duration(milliseconds: 10),
);

class Rig {
  Rig({
    SessionTiming timing = fastTiming,
    bool autoFrames = true,
    ScreenInfo screen = const ScreenInfo(w: 1440, h: 900),
    Assignment? assignment,
    AssignmentsRepository? assignments,
    ProfileRepository? profile,
    LiveRepository? live,
    SpeechSynthesizer? speech,
    AudioRecorderFactory? audioRecorder,
    int? seed,
    List<String> cameras = const ['Fake camera'],
  })  : repo = FakeSessionRepository(),
        gaze = FakeGazeEstimator(),
        frames = FakeFrameSource(autoFrames: autoFrames, labels: cameras) {
    controller = SessionFlowController(
      repository: repo,
      gaze: gaze,
      frames: frames,
      device: const DeviceInfo(platform: 'web', userAgent: 'test-agent'),
      timing: timing,
      assignment: assignment,
      assignments: assignments,
      profile: profile,
      live: live,
      speech: speech,
      audioRecorder: audioRecorder,
      random: seed == null ? null : math.Random(seed),
    )..updateScreen(screen);
  }

  final FakeSessionRepository repo;
  final FakeGazeEstimator gaze;
  final FakeFrameSource frames;
  late final SessionFlowController controller;

  /// Every distinct step the controller passed through.
  final List<SessionStep> steps = [];

  void trackSteps() {
    steps.add(controller.step);
    controller.addListener(() {
      if (steps.last != controller.step) steps.add(controller.step);
    });
  }

  Future<void> toCameraCheck() async {
    await controller.loadIntro();
    await controller.begin();
  }

  Future<void> toCalibration() async {
    await toCameraCheck();
    await controller.runCameraCheck();
    controller.continueToCalibration();
  }

  Future<void> throughCalibration() async {
    await toCalibration();
    await controller.startCalibration();
    controller.continueToValidation();
  }

  Future<void> throughValidation() async {
    await throughCalibration();
    await controller.startValidation();
  }

  Future<void> toBaseline() async {
    await throughValidation();
    controller.continueToBaseline();
  }

  /// Runs the baseline of a protocol session to its end: the flow then
  /// waits at the practice instructions.
  Future<void> toPractice() async {
    await toBaseline();
    await controller.startBaseline();
    await until(() => controller.step == SessionStep.practice,
        what: 'the practice step');
  }

  void dispose() => controller.dispose();
}

/// Polls until [condition] holds, or fails after [timeout].
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String what = 'condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Lets pending microtasks and zero-delay timers run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

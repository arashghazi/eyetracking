import 'package:eyetracking_core/eyetracking_core.dart';

/// What the participant's session flow needs from the research server.
/// Every method maps to one `/me/...` endpoint of the step 2 contract.
abstract class SessionRepository {
  Future<MeasurementSettings> measurementSettings();

  /// Why the participant may not start a session (used after a 403).
  Future<Readiness> readiness();

  /// Creates a session; throws an [ApiException] with status 403 when the
  /// participant is not ready.
  Future<SessionSummary> create(SessionCreateRequest request);

  Future<SessionSummary> cameraCheck(String sessionId, CameraCheckRequest body);

  Future<CalibrationResult> calibrate(
    String sessionId,
    List<CalibrationTargetCapture> targets,
  );

  Future<ValidationResult> validate(
    String sessionId,
    StimulusLayout layout,
    List<ValidationTargetCapture> targets,
  );

  /// Posts the stimulus layout used to classify the following samples. For
  /// a practice stage the layout also carries its [stageIndex].
  Future<void> postLayout(
    String sessionId,
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  });

  Future<SampleAck> postSamples(String sessionId, List<RawGazeSample> samples);

  Future<SessionSummary> postEvent(
    String sessionId,
    SessionEventType type, {
    required int tMs,
    Map<String, dynamic>? payload,
  });

  Future<SessionSummary> summary(String sessionId);

  /// Step 3: the trials of one finished stage, in one batch.
  Future<TrialAck> postTrials(String sessionId, List<TrialRecord> trials);

  /// Step 3: asks the server what to do after a stage.
  Future<StageDecision> stageResult(
    String sessionId,
    int stageIndex, {
    int? comfortValue,
  });

  /// Step 3: an interaction or comprehension answer.
  Future<AnswerResult> postAnswer(String sessionId, AnswerRequest answer);

  /// The participant's own sessions, newest first.
  Future<List<SessionSummary>> mine();
}

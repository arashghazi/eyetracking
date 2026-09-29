import 'package:eyetracking_core/eyetracking_core.dart';

/// How a practice controller opens and closes the recorded segments of the
/// session. The session flow implements it: it owns the camera, the gaze
/// stream and the sample upload, the practice controllers own what is shown.
abstract interface class SegmentRecorder {
  /// Milliseconds on the session clock.
  int get nowMs;

  /// Posts [layout] (with [stageIndex] for a practice stage), opens the
  /// segment on the server and starts streaming gaze samples.
  Future<void> openSegment(
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  });

  /// Posts a new layout for the segment that is running, for example after
  /// the window was resized.
  Future<void> updateLayout(
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  });

  /// Stops streaming, uploads the samples that are left and closes the
  /// segment.
  Future<void> closeSegment(SessionSegmentName segment);
}

/// How a practice ended.
enum PracticeEnd {
  /// Every stage or the whole conversation was done.
  completed,

  /// The protocol stopped the practice because of low comfort.
  stopped,
}

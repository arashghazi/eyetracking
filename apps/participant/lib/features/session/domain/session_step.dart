/// Steps of the guided session, in order.
enum SessionStep {
  intro('Introduction'),
  cameraCheck('Camera check'),
  calibration('Calibration'),
  validation('Validation'),
  baseline('Baseline'),
  summary('Summary');

  const SessionStep(this.label);
  final String label;

  /// Steps shown in the visible step list (the introduction is not one).
  static const listed = [
    cameraCheck,
    calibration,
    validation,
    baseline,
    summary,
  ];

  /// Position in [listed], or -1 for the introduction.
  int get listIndex => listed.indexOf(this);

  /// Pause and End are offered from calibration onward.
  bool get hasSessionControls =>
      this == calibration || this == validation || this == baseline;
}

/// What the current step is doing.
enum StepPhase {
  /// Instructions are shown; the participant starts the step.
  idle,

  /// 3-2-1 before the first target.
  countdown,

  /// A target is on screen (settling or capturing).
  capturing,

  /// Waiting for the server to evaluate the captured samples.
  posting,

  /// The calibration or validation result is shown.
  result,

  /// Baseline stimulus is running.
  running,

  /// Paused by the participant.
  paused,

  /// Camera, orientation or zoom changed: calibrate again.
  changed,
}

enum TargetStage { settling, capturing }

/// Timings of the guided flow. Tests shrink them.
class SessionTiming {
  const SessionTiming({
    this.countdownFrom = 3,
    this.countdownStep = const Duration(seconds: 1),
    this.settle = const Duration(milliseconds: 800),
    this.calibrationCapture = const Duration(milliseconds: 1200),
    this.validationCapture = const Duration(milliseconds: 1500),
    this.baseline = const Duration(seconds: 30),
    this.faceLostAfter = const Duration(seconds: 1),
    this.progressTick = const Duration(milliseconds: 250),
    this.batchSize = 10,
    this.fps = 10,
    this.cameraCheckFrames = 5,
    this.cameraCheckFps = 5,
    this.cameraCheckTimeout = const Duration(seconds: 10),
  });

  final int countdownFrom;
  final Duration countdownStep;
  final Duration settle;
  final Duration calibrationCapture;
  final Duration validationCapture;
  final Duration baseline;
  final Duration faceLostAfter;
  final Duration progressTick;
  final int batchSize;

  /// Upper bound for frames per second; the gaze service may allow fewer.
  final double fps;
  final int cameraCheckFrames;
  final double cameraCheckFps;
  final Duration cameraCheckTimeout;
}

/// Result of the camera check.
class CameraCheckOutcome {
  const CameraCheckOutcome({
    required this.passed,
    required this.framesWithFace,
    required this.framesSampled,
    required this.faceConf,
  });

  final bool passed;
  final int framesWithFace;
  final int framesSampled;
  final double faceConf;
}

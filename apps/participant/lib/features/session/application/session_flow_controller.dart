import 'dart:async';
import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';

import '../../assignments/domain/assignments_repository.dart';
import '../../profile/domain/profile_repository.dart';
import '../domain/live_repository.dart';
import '../domain/number_placement.dart';
import '../domain/session_repository.dart';
import '../domain/session_step.dart';
import '../domain/stimulus_geometry.dart';
import 'gradual_practice_controller.dart';
import 'interest_practice_controller.dart';
import 'live_practice_controller.dart';
import 'segment_recorder.dart';

/// Runs the guided session: introduction, camera check, calibration,
/// validation, baseline observation and summary. With an [assignment] the
/// session runs a practice protocol (step 3): after the baseline come the
/// practice, a prompt-free post observation, the comfort question and the
/// summary.
///
/// One instance drives one session. All work that can be interrupted (a
/// capture, the baseline stream) runs under a run token: pause, end, a device
/// change or disposal bump the token, and whatever the interrupted work still
/// produces is discarded.
class SessionFlowController extends SafeChangeNotifier {
  SessionFlowController({
    required SessionRepository repository,
    required this._gaze,
    required this._frames,
    required this._device,
    this.timing = const SessionTiming(),
    this.assignment,
    this._assignments,
    ProfileRepository? profile,
    LiveRepository? live,
    this._speech,
    this._audioRecorder,
    math.Random? random,
  })  : _repo = repository,
        _liveRepo = live,
        _profileRepo = profile,
        _random = random ?? math.Random() {
    _recorder = _FlowRecorder(this);
  }

  final SessionRepository _repo;
  final GazeEstimator _gaze;
  final FrameSource _frames;
  final DeviceInfo _device;
  final SessionTiming timing;

  /// The assignment this session runs; null for a measurement-only session.
  final Assignment? assignment;
  final AssignmentsRepository? _assignments;
  final ProfileRepository? _profileRepo;

  // Step 7: the live conversation's server port, the avatar's voice and the
  // microphone (all optional: a session without a live path needs none).
  final LiveRepository? _liveRepo;
  final SpeechSynthesizer? _speech;
  final AudioRecorderFactory? _audioRecorder;
  final math.Random _random;
  late final SegmentRecorder _recorder;

  // ------------------------------------------------------------- state

  SessionStep _step = SessionStep.intro;
  StepPhase _phase = StepPhase.idle;
  bool _busy = false;
  String? _error;
  ScreenInfo _screen = const ScreenInfo(w: 1280, h: 720);

  MeasurementSettings? _settings;
  GazeInfo? _gazeInfo;
  SessionSummary? _session;
  List<String>? _blockedReasons;

  CameraCheckOutcome? _cameraOutcome;

  CalibrationResult? _calibration;
  List<TargetPoint> _calibrationPoints = const [];
  int _targetIndex = 0;
  TargetStage _stage = TargetStage.settling;
  int _countdown = 0;

  FaceLayout? _faceLayout;
  List<ValidationTargetSpec> _validationSpecs = const [];
  ValidationResult? _validation;

  // Step 3
  Profile? _profileData;
  ProtocolDefinition? _protocolDef;
  GradualPracticeController? _gradual;
  InterestPracticeController? _interest;
  LivePracticeController? _live;
  bool _baselineDone = false;
  SessionSegmentName? _openSegment;
  SessionSegmentName _observation = SessionSegmentName.baseline;

  int _baselineElapsedMs = 0;
  bool _faceLost = false;
  int _lastFaceMs = 0;
  int _storedSamples = 0;
  int _invalidSamples = 0;
  String? _streamProblem;
  int _gazeFailures = 0;

  FrameSourceEvent? _change;
  SessionSummary? _summary;
  bool _ended = false;
  String _endReason = EndReason.completed;

  // ------------------------------------------------------ run machinery

  int _token = 0;
  StreamSubscription<CapturedFrame>? _frameSub;
  StreamSubscription<FrameSourceEvent>? _eventSub;
  bool _estimating = false;
  // Created on first use so awaiting them never depends on the zone the
  // controller was constructed in.
  Future<void>? _inFlight;
  List<RawGazeSample>? _collector;
  void Function(CapturedFrame frame, RawGazeSample? sample)? _streamHandler;

  /// True while a pause or resume is still talking to the camera and server.
  bool _switching = false;

  final Stopwatch _baselineWatch = Stopwatch();
  final List<RawGazeSample> _pending = [];
  Future<void>? _postChain;

  // ----------------------------------------------------------- getters

  SessionStep get step => _step;
  StepPhase get phase => _phase;
  bool get busy => _busy;
  String? get error => _error;
  ScreenInfo get screen => _screen;

  MeasurementSettings? get settings => _settings;
  GazeInfo? get gazeInfo => _gazeInfo;
  SessionSummary? get session => _session;

  /// Ready-to-start data for the introduction has been loaded.
  bool get introReady => _settings != null && _gazeInfo != null;

  /// Readiness reasons when the server refused to create the session.
  List<String>? get blockedReasons => _blockedReasons;

  CameraCheckOutcome? get cameraOutcome => _cameraOutcome;

  CalibrationResult? get calibration => _calibration;
  List<TargetPoint> get calibrationPoints => _calibrationPoints;
  int get targetIndex => _targetIndex;
  TargetStage get stage => _stage;
  int get countdown => _countdown;

  StimulusLayout? get layout => _faceLayout?.layout;
  FaceLayout? get faceLayout => _faceLayout;
  List<ValidationTargetSpec> get validationSpecs => _validationSpecs;
  ValidationResult? get validation => _validation;

  bool get allowContinueWithoutValidation =>
      _settings?.allowContinueWithoutValidation ?? false;

  /// True when the session runs a practice protocol.
  bool get hasProtocol => assignment != null;

  /// The frozen protocol version this session runs (after it was created).
  ProtocolDefinition? get protocol => _protocolDef;
  bool get isInterest => _protocolDef?.path == ProtocolPath.interestConversation;

  /// The session runs the live conversation with an avatar (step 7).
  bool get isLive => _protocolDef?.path == ProtocolPath.liveConversation;
  Profile? get profile => _profileData;
  GradualPracticeController? get gradual => _gradual;
  InterestPracticeController? get interest => _interest;
  LivePracticeController? get live => _live;

  /// Captions are shown only for participants who asked for them.
  bool get showCaptions => _profileData?.accessibilityNeeds
          .any((n) => n.toLowerCase().contains('caption')) ??
      false;

  /// Height kept free at the bottom for the response controls.
  double get practiceBottomInset =>
      hasProtocol ? practiceBarReserve(_screen) : 16;

  /// Length of the baseline: the protocol's, or the plain default.
  Duration get baselineDuration => _protocolDef == null
      ? timing.baseline
      : timing.seconds(_protocolDef!.baselineSeconds);

  /// Length of the post observation.
  Duration get postDuration => _protocolDef == null
      ? timing.baseline
      : timing.seconds(_protocolDef!.postSeconds);

  Duration get _observationDuration => _observation == SessionSegmentName.post
      ? postDuration
      : baselineDuration;

  double get observationProgress {
    final total = _observationDuration.inMilliseconds;
    return total == 0 ? 1 : (_baselineElapsedMs / total).clamp(0.0, 1.0);
  }

  double get baselineProgress => observationProgress;

  /// Level of the face drawn during the observation: the placeholder face
  /// for the baseline, the face of the last practice stage for the post
  /// observation.
  int get observationFaceLevel {
    if (_step == SessionStep.post) {
      final g = _gradual;
      if (g != null) return g.stage.faceLevel;
    }
    return 2;
  }

  /// The practice, the interest post video or the live avatar's post
  /// observation is on the screen.
  bool get practiceVisible =>
      _phase == StepPhase.running &&
      (_step == SessionStep.practice ||
          (_step == SessionStep.post && (isInterest || isLive)));

  /// The comfort question at the end of a protocol session is shown.
  bool get askingComfort => _step == SessionStep.summary && _phase == StepPhase.comfort;

  bool get faceLost => _faceLost;
  int get storedSamples => _storedSamples;
  int get invalidSamples => _invalidSamples;

  /// Shown when the gaze service stops answering during the baseline.
  String? get streamProblem => _streamProblem;

  FrameSourceEvent? get change => _change;
  SessionSummary? get summary => _summary;
  bool get isEnded => _ended;
  FrameSource get frameSource => _frames;

  /// Pause is offered while something is being recorded.
  bool get canPause =>
      _step.hasSessionControls &&
      (_phase == StepPhase.countdown ||
          _phase == StepPhase.capturing ||
          _phase == StepPhase.running);

  /// Resume is offered once a pause has finished and no device change
  /// invalidated the calibration.
  bool get canResume =>
      _phase == StepPhase.paused && !_switching && _change == null;

  bool get canEnd =>
      _step.hasSessionControls && _session != null && !_ended && !_busy;

  /// The stimulus (dots, face card) is on screen, not an instruction panel.
  bool get stimulusVisible =>
      (_step == SessionStep.calibration || _step == SessionStep.validation)
          ? (_phase == StepPhase.countdown || _phase == StepPhase.capturing)
          : (_isObservationStep &&
              (_phase == StepPhase.running || _phase == StepPhase.paused));

  /// Baseline, and the post observation of the gradual path: a face and a
  /// progress bar, nothing to do.
  bool get _isObservationStep =>
      _step == SessionStep.baseline ||
      (_step == SessionStep.post && !isInterest && !isLive);

  bool get hasActiveSession =>
      _session != null &&
      !_ended &&
      _step != SessionStep.intro &&
      (_step != SessionStep.summary || _phase == StepPhase.comfort);

  /// Records the current screen; used when the session is created and when
  /// stimuli are laid out. Does not notify (safe to call while building).
  void updateScreen(ScreenInfo screen) => _screen = screen;

  void dismissError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ intro

  Future<void> loadIntro() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _settings ??= await _repo.measurementSettings();
      _gazeInfo = await _gaze.info();
    } catch (e) {
      _error = userMessage(e);
    }
    // The profile (response mode, captions) only shapes the practice; the
    // session can start without it.
    if (hasProtocol && _profileData == null && _profileRepo != null) {
      try {
        _profileData = await _profileRepo.load();
      } catch (_) {
        // Defaults: number entry, no captions.
      }
    }
    _busy = false;
    notifyListeners();
  }

  /// Starts the camera and creates the session on the server.
  Future<void> begin() async {
    if (_busy || !introReady || _session != null) return;
    _busy = true;
    _error = null;
    _blockedReasons = null;
    notifyListeners();
    try {
      final started = await _startCamera();
      if (!started) return;
      try {
        final label = _frames.activeCameraLabel ??
            (_frames.cameraLabels.isEmpty ? null : _frames.cameraLabels.first);
        _session = await _repo.create(SessionCreateRequest(
          device: _device,
          screen: _screen,
          camera: CameraInfo(
            label: label,
            w: _frames.frameWidth == 0 ? 640 : _frames.frameWidth,
            h: _frames.frameHeight == 0 ? 480 : _frames.frameHeight,
          ),
          gazeModel: _gazeInfo!,
          assignmentId: assignment?.id,
        ));
        if (hasProtocol) {
          _protocolDef =
              _session!.protocol?.definition ?? assignment!.protocol.definition;
          if (_protocolDef == null) {
            await _frames.stop();
            _error = 'The session was created without its protocol. Please '
                'try again or ask your researcher.';
            _session = null;
            return;
          }
        }
        _frames.restartClock();
        _eventSub ??= _frames.events.listen(_onFrameSourceEvent);
        _step = SessionStep.cameraCheck;
        _phase = StepPhase.idle;
      } on ApiException catch (e) {
        await _frames.stop();
        if (e.isForbidden) {
          _blockedReasons = await _readinessReasons(e);
        } else {
          _error = e.message;
        }
      } catch (e) {
        await _frames.stop();
        _error = userMessage(e);
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<List<String>> _readinessReasons(ApiException forbidden) async {
    try {
      final readiness = await _repo.readiness();
      if (readiness.reasons.isNotEmpty) {
        return [for (final r in readiness.reasons) readinessReasonLabel(r)];
      }
    } catch (_) {
      // Fall back to the server's own sentence.
    }
    return [
      for (final part in forbidden.message.split(RegExp(r'[;,]\s*')))
        if (part.trim().isNotEmpty) readinessReasonLabel(part.trim()),
    ];
  }

  /// Opens the camera; false (with [error] set) when that fails.
  Future<bool> _startCamera() async {
    try {
      await _frames.start();
      return true;
    } on UnsupportedError catch (e) {
      _error = e.message?.toString() ?? 'Camera capture is not available here.';
    } on FrameSourceException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'The camera could not be started. Check it and try again.';
    }
    return false;
  }

  // ----------------------------------------------------- camera check

  /// Samples a few frames and reports whether a face is clearly visible.
  Future<void> runCameraCheck() async {
    final session = _session;
    if (_busy || session == null || _step != SessionStep.cameraCheck) return;
    _busy = true;
    _error = null;
    _cameraOutcome = null;
    notifyListeners();
    final token = ++_token;
    try {
      if (!_frames.isActive && !await _startCamera()) return;
      final samples = <RawGazeSample>[];
      Object? firstFailure;
      var w = _frames.frameWidth, h = _frames.frameHeight;
      var received = 0;
      try {
        final stream = _frames
            .frames(fps: timing.cameraCheckFps)
            .take(timing.cameraCheckFrames)
            .timeout(timing.cameraCheckTimeout);
        await for (final frame in stream) {
          if (!_alive(token)) return;
          received++;
          w = frame.width;
          h = frame.height;
          try {
            samples
                .add(await _gaze.estimate(frame.jpeg, frame.tMs, w, h));
          } catch (e) {
            firstFailure ??= e;
          }
        }
      } on TimeoutException {
        _error = 'The camera is not delivering pictures. Check it and try again.';
        return;
      }
      if (!_alive(token)) return;
      if (samples.isEmpty && firstFailure != null) {
        _error = userMessage(firstFailure);
        return;
      }
      final withFace =
          samples.where((s) => s.faceDetected && s.faceConf >= 0.5).toList();
      final passed = withFace.length >= 3;
      final conf = withFace.isEmpty
          ? samples.fold<double>(0, (m, s) => math.max(m, s.faceConf))
          : withFace.fold<double>(0, (a, s) => a + s.faceConf) /
              withFace.length;
      final outcome = CameraCheckOutcome(
        passed: passed,
        framesWithFace: withFace.length,
        framesSampled: math.max(received, samples.length),
        faceConf: conf,
      );
      _session = await _repo.cameraCheck(
        session.id,
        CameraCheckRequest(
          faceDetected: passed,
          faceConf: conf,
          // The estimator only reports a face when the picture is usable.
          lightingOk: passed,
          frameW: w,
          frameH: h,
          cameraLabel: _frames.activeCameraLabel,
        ),
      );
      _cameraOutcome = outcome;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Switches to another camera before calibration. The face check has to
  /// pass again with the new camera; the choice is remembered on this device.
  Future<void> selectCamera(String deviceId) async {
    if (_busy || _session == null || _step != SessionStep.cameraCheck) return;
    if (deviceId == _frames.activeCameraId) return;
    _busy = true;
    _error = null;
    _cameraOutcome = null;
    ++_token;
    notifyListeners();
    try {
      await _frames.selectCamera(deviceId);
    } on FrameSourceException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'The camera could not be started. Check it and try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void continueToCalibration() {
    if (_cameraOutcome?.passed != true) return;
    _step = SessionStep.calibration;
    _phase = StepPhase.idle;
    _error = null;
    notifyListeners();
  }

  // ------------------------------------------------------ calibration

  /// Shows the calibration dots one at a time and posts what was captured.
  Future<void> startCalibration() async {
    final session = _session;
    final settings = _settings;
    if (session == null || settings == null) return;
    if (_step != SessionStep.calibration) return;
    if (_phase != StepPhase.idle && _phase != StepPhase.result) return;
    final token = ++_token;
    _error = null;
    _calibration = null;
    _validation = null;
    _change = null;
    _calibrationPoints = calibrationTargets(settings.calibrationPoints, _screen);
    _targetIndex = 0;
    _phase = StepPhase.countdown;
    _countdown = timing.countdownFrom;
    notifyListeners();
    if (!_frames.isActive && !await _startCamera()) {
      _phase = StepPhase.idle;
      notifyListeners();
      return;
    }
    final captured = await _runCapture(
      token,
      _calibrationPoints.length,
      timing.calibrationCapture,
    );
    if (captured == null) return;
    if (captured.every((s) => s.isEmpty)) {
      _fail(token, 'No pictures could be analysed. Check the camera and the '
          'gaze service, then try again.');
      return;
    }
    _phase = StepPhase.posting;
    notifyListeners();
    try {
      final result = await _repo.calibrate(session.id, [
        for (var i = 0; i < captured.length; i++)
          CalibrationTargetCapture(
            x: _calibrationPoints[i].x,
            y: _calibrationPoints[i].y,
            samples: captured[i],
          ),
      ]);
      if (!_alive(token)) return;
      _calibration = result;
      _phase = StepPhase.result;
      notifyListeners();
    } catch (e) {
      _fail(token, userMessage(e));
    }
  }

  void continueToValidation() {
    if (_calibration?.accepted != true || _step != SessionStep.calibration) {
      return;
    }
    _step = SessionStep.validation;
    _phase = StepPhase.idle;
    _validation = null;
    _error = null;
    notifyListeners();
  }

  // -------------------------------------------------------- validation

  /// Shows the face card and the seven validation dots, then posts them with
  /// the layout.
  Future<void> startValidation() async {
    final session = _session;
    final calibration = _calibration;
    if (session == null || calibration == null) return;
    if (_step != SessionStep.validation) return;
    if (_phase != StepPhase.idle && _phase != StepPhase.result) return;
    final token = ++_token;
    _error = null;
    _validation = null;
    final faceLayout = buildFaceLayout(
      screen: _screen,
      residualPx: calibration.residualPxMedian,
      bottomInset: practiceBottomInset,
    );
    _faceLayout = faceLayout;
    _validationSpecs = validationTargets(faceLayout.layout);
    _targetIndex = 0;
    _phase = StepPhase.countdown;
    _countdown = timing.countdownFrom;
    notifyListeners();
    if (!_frames.isActive && !await _startCamera()) {
      _phase = StepPhase.idle;
      notifyListeners();
      return;
    }
    final captured = await _runCapture(
      token,
      _validationSpecs.length,
      timing.validationCapture,
    );
    if (captured == null) return;
    if (captured.every((s) => s.isEmpty)) {
      _fail(token, 'No pictures could be analysed. Check the camera and the '
          'gaze service, then try again.');
      return;
    }
    _phase = StepPhase.posting;
    notifyListeners();
    try {
      final result = await _repo.validate(session.id, faceLayout.layout, [
        for (var i = 0; i < captured.length; i++)
          ValidationTargetCapture(
            region: _validationSpecs[i].region,
            x: _validationSpecs[i].x,
            y: _validationSpecs[i].y,
            samples: captured[i],
          ),
      ]);
      if (!_alive(token)) return;
      _validation = result;
      _phase = StepPhase.result;
      notifyListeners();
    } catch (e) {
      _fail(token, userMessage(e));
    }
  }

  /// Back to the calibration instructions (after a failed validation or a
  /// device change).
  void recalibrate() {
    if (_session == null || _ended) return;
    _cancelRun();
    _step = SessionStep.calibration;
    _phase = StepPhase.idle;
    _calibration = null;
    _validation = null;
    _faceLayout = null;
    _change = null;
    _error = null;
    _pending.clear();
    notifyListeners();
  }

  void continueToBaseline() {
    if (_step != SessionStep.validation || _phase != StepPhase.result) return;
    final v = _validation;
    if (v == null) return;
    if (!v.passed && !allowContinueWithoutValidation) return;
    // After a device change the baseline is already done: carry on with the
    // practice (or the post observation) where the participant left off.
    _step = _baselineDone
        ? (_practiceEnded ? SessionStep.post : SessionStep.practice)
        : SessionStep.baseline;
    _phase = StepPhase.idle;
    _error = null;
    notifyListeners();
  }

  // ------------------------------------------------ baseline and post

  /// Posts the layout, opens the baseline segment and streams gaze samples
  /// for the baseline duration.
  Future<void> startBaseline() =>
      _startObservation(SessionSegmentName.baseline, SessionStep.baseline);

  /// Starts the post observation of the gradual path: the face of the last
  /// practice stage, prompt-free, for the protocol's post duration. On the
  /// interest path the post segment video plays instead.
  Future<void> startPost() async {
    if (_step != SessionStep.post || _phase != StepPhase.idle) return;
    if (isInterest) {
      final i = _interest;
      if (i == null) return;
      _error = null;
      _phase = StepPhase.running;
      notifyListeners();
      i.startPost();
      return;
    }
    if (isLive) {
      final l = _live;
      if (l == null) return;
      _error = null;
      _phase = StepPhase.running;
      notifyListeners();
      // After a device change the post observation goes on where it was.
      if (l.phase == LivePhase.post) {
        l.restartCurrent();
      } else {
        l.startPost(postDuration);
      }
      return;
    }
    await _startObservation(SessionSegmentName.post, SessionStep.post);
  }

  Future<void> _startObservation(
    SessionSegmentName segment,
    SessionStep expected,
  ) async {
    final session = _session;
    final layout = this.layout;
    if (session == null || layout == null) return;
    if (_step != expected || _phase != StepPhase.idle) return;
    final token = ++_token;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (!_frames.isActive && !await _startCamera()) return;
      await _repo.postLayout(session.id, segment, layout);
      if (!_alive(token)) return;
      await _repo.postEvent(
        session.id,
        SessionEventType.segmentStart,
        tMs: _frames.nowMs,
        payload: {'segment': segment.wire},
      );
      _openSegment = segment;
    } catch (e) {
      _error = userMessage(e);
      return;
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (!_alive(token)) return;
    _observation = segment;
    _baselineElapsedMs = 0;
    _baselineWatch
      ..reset()
      ..start();
    _faceLost = false;
    _gazeFailures = 0;
    _streamProblem = null;
    if (segment == SessionSegmentName.baseline) {
      _storedSamples = 0;
      _invalidSamples = 0;
    }
    _phase = StepPhase.running;
    notifyListeners();
    unawaited(_runObservation(token));
  }

  Future<void> _runObservation(int token) async {
    final duration = _observationDuration;
    _lastFaceMs = _frames.nowMs;
    _startPump(token, handler: _onStreamFrame);
    while (_alive(token) && _baselineWatch.elapsed < duration) {
      await Future<void>.delayed(timing.progressTick);
      if (!_alive(token)) return;
      _baselineElapsedMs = _baselineWatch.elapsedMilliseconds;
      notifyListeners();
    }
    if (!_alive(token)) return;
    _baselineElapsedMs = duration.inMilliseconds;
    await _stopPump();
    await _inFlight;
    if (!_alive(token)) return;
    _baselineWatch.stop();
    await _flushSamples();
    if (!_alive(token)) return;
    await _sendEvent(SessionEventType.segmentEnd,
        payload: {'segment': _observation.wire});
    _openSegment = null;
    if (!_alive(token)) return;
    if (_observation == SessionSegmentName.baseline) {
      await _afterBaseline();
    } else {
      _enterComfort();
    }
  }

  Future<void> _afterBaseline() async {
    if (!hasProtocol) {
      await _enterSummary();
      return;
    }
    _baselineDone = true;
    _step = SessionStep.practice;
    _phase = StepPhase.idle;
    notifyListeners();
  }

  void _onStreamFrame(CapturedFrame frame, RawGazeSample? sample) {
    if (sample != null) {
      _pending.add(sample);
      if (_pending.length >= timing.batchSize) _enqueuePost(_takePending());
    }
    final sawFace = sample != null && sample.faceDetected;
    if (sawFace) {
      _lastFaceMs = frame.tMs;
      if (_faceLost) {
        _faceLost = false;
        unawaited(_sendEvent(SessionEventType.faceFound, tMs: frame.tMs));
        notifyListeners();
      }
    } else if (sample != null &&
        !_faceLost &&
        frame.tMs - _lastFaceMs >= timing.faceLostAfter.inMilliseconds) {
      _faceLost = true;
      unawaited(_sendEvent(SessionEventType.faceLost, tMs: frame.tMs));
      notifyListeners();
    }
    if (sample == null && _gazeFailures >= 5 && _streamProblem == null) {
      _streamProblem = 'The gaze service is not answering. Nothing is being '
          'recorded until it is back.';
      notifyListeners();
    } else if (sample != null && _streamProblem != null) {
      _streamProblem = null;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------- practice

  bool _practiceEnded = false;

  /// Starts the practice (or carries it on after a device change).
  Future<void> startPractice() async {
    final protocol = _protocolDef;
    final session = _session;
    if (_step != SessionStep.practice || _phase != StepPhase.idle) return;
    if (protocol == null || session == null || _busy) return;
    _error = null;
    if (protocol.path == ProtocolPath.gradualFace) {
      final layout = this.layout;
      if (layout == null) return;
      var g = _gradual;
      final first = g == null;
      if (g == null) {
        g = GradualPracticeController(
          sessionId: session.id,
          protocol: protocol,
          layout: layout,
          repository: _repo,
          recorder: _recorder,
          profileMode: _profileData?.responseMode ?? ResponseMode.keyboard,
          timing: timing,
          bottomInset: practiceBottomInset,
          random: _random,
          onFinished: _practiceFinished,
        );
        _gradual = g;
      } else {
        g.layout = layout;
      }
      _phase = StepPhase.running;
      notifyListeners();
      unawaited(first ? g.startStage() : g.resumeAfterInterruption());
      return;
    }
    if (protocol.path == ProtocolPath.liveConversation) {
      var l = _live;
      if (l != null) {
        // After a device change the conversation goes on where it was.
        _phase = StepPhase.running;
        notifyListeners();
        l.restartCurrent();
        return;
      }
      final repo = _liveRepo;
      final speech = _speech;
      if (repo == null || speech == null) {
        _error = 'The live conversation is not available here.';
        notifyListeners();
        return;
      }
      l = LivePracticeController(
        sessionId: session.id,
        repository: repo,
        recorder: _recorder,
        screen: () => _screen,
        speech: speech,
        audioRecorder: _audioRecorder,
        closingFallback: _closingLine(protocol),
        onFinished: _practiceFinished,
        onPostFinished: _postFinished,
      );
      _live = l;
      _phase = StepPhase.running;
      notifyListeners();
      unawaited(l.load());
      return;
    }
    // Interest conversation: fetch the personalized content first.
    var i = _interest;
    if (i != null) {
      _phase = StepPhase.running;
      notifyListeners();
      i.restartCurrent();
      return;
    }
    final assignments = _assignments;
    final a = assignment;
    if (assignments == null || a == null) {
      _error = 'The conversation content is not available here.';
      notifyListeners();
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final content = await assignments.content(a.id);
      i = InterestPracticeController(
        sessionId: session.id,
        content: content,
        reloadContent: () => assignments.content(a.id),
        repository: _repo,
        recorder: _recorder,
        screen: () => _screen,
        showCaptions: showCaptions,
        onFinished: _practiceFinished,
        onPostFinished: _postFinished,
      );
      _interest = i;
      _phase = StepPhase.running;
      _busy = false;
      notifyListeners();
      i.start();
    } catch (e) {
      _busy = false;
      _error = userMessage(e);
      notifyListeners();
    }
  }

  /// The protocol's closing line with the participant's name and topic, for
  /// when the server's closing turn comes without its text.
  String _closingLine(ProtocolDefinition protocol) => renderLiveLine(
        protocol.live?.closingLine ?? LiveProtocolConfig.defaultClosingLine,
        displayName: _profileData?.displayName,
        topic: assignment?.topic ?? '',
      );

  void _practiceFinished(PracticeEnd end) {
    if (isDisposed || _ended) return;
    _practiceEnded = true;
    if (end == PracticeEnd.stopped) {
      // The protocol stops the practice after low comfort: no more looking
      // at faces, the session ends here with a polite summary.
      _endReason = EndReason.endedEarly;
      unawaited(_enterSummary());
      return;
    }
    _step = SessionStep.post;
    _phase = StepPhase.idle;
    notifyListeners();
  }

  void _postFinished() {
    if (isDisposed || _ended) return;
    _enterComfort();
  }

  // ------------------------------------------------ comfort at the end

  void _enterComfort() {
    _step = SessionStep.summary;
    _phase = StepPhase.comfort;
    _busy = false;
    _error = null;
    notifyListeners();
    unawaited(_frames.stop());
  }

  /// The participant answered the final comfort question.
  Future<void> answerFinalComfort(int value) async {
    if (_phase != StepPhase.comfort) return;
    _busy = true;
    _error = null;
    notifyListeners();
    await _sendEvent(
      SessionEventType.comfortAnswer,
      payload: {'value': value, 'segment': SessionSegmentName.post.wire},
    );
    await _enterSummary();
  }

  /// Goes to the summary without answering the final comfort question.
  Future<void> skipFinalComfort() async {
    if (_phase != StepPhase.comfort) return;
    _busy = true;
    notifyListeners();
    await _enterSummary();
  }

  // ------------------------------------------------------ pause / end

  /// True while a segment is open on the server (samples are being sent).
  bool get _segmentRunning => _openSegment != null;

  /// Pauses what is running. While a segment is open this sends `pause` and
  /// stops the camera; between segments, and during calibration or
  /// validation, it only stops locally (the server has no segment running).
  Future<void> pause() async {
    if (!canPause || _switching) return;
    _switching = true;
    final segmentRunning = _segmentRunning;
    _cancelRun();
    _baselineWatch.stop();
    _gradual?.pause();
    _interest?.pause();
    _live?.pause();
    await _stopPump();
    _phase = StepPhase.paused;
    _faceLost = false;
    notifyListeners();
    try {
      if (segmentRunning) {
        await _flushSamples();
        await _sendEvent(SessionEventType.pause);
      }
      await _frames.stop();
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// Continues after [pause]. Observations and practice restart streaming;
  /// calibration and validation return to their instructions.
  Future<void> resume() async {
    if (!canResume) return;
    _switching = true;
    try {
      if (!await _startCamera()) {
        notifyListeners();
        return;
      }
      if (!_step.hasSessionControls ||
          _step == SessionStep.calibration ||
          _step == SessionStep.validation) {
        _phase = StepPhase.idle;
        notifyListeners();
        return;
      }
      final token = ++_token;
      final segmentRunning = _segmentRunning;
      if (segmentRunning) {
        await _sendEvent(SessionEventType.resume);
        if (!_alive(token)) return;
      }
      if (_isObservationStep) {
        _baselineWatch.start();
        _phase = StepPhase.running;
        notifyListeners();
        unawaited(_runObservation(token));
        return;
      }
      // Practice or the interest post video.
      if (segmentRunning) {
        _lastFaceMs = _frames.nowMs;
        _startPump(token, handler: _onStreamFrame);
      }
      _phase = StepPhase.running;
      notifyListeners();
      final g = _gradual;
      if (_step == SessionStep.practice && g != null) g.resume();
      _interest?.resume();
      _live?.resume();
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// Ends the session early and shows the summary.
  Future<void> endEarly() async {
    if (_session == null || _ended) return;
    if (_step == SessionStep.summary && _phase != StepPhase.comfort) return;
    final wasStreaming = _segmentRunning;
    _cancelRun();
    _baselineWatch.stop();
    _gradual?.cancel();
    _interest?.cancel();
    _live?.cancel();
    await _stopPump();
    if (wasStreaming) await _flushSamples();
    _openSegment = null;
    _endReason = EndReason.endedEarly;
    await _enterSummary();
  }

  // ------------------------------------------------------ device change

  void _onFrameSourceEvent(FrameSourceEvent event) {
    if (!_step.hasSessionControls || _ended || _phase == StepPhase.changed) {
      return;
    }
    final wasRunning = _segmentRunning && _phase == StepPhase.running;
    _cancelRun();
    _baselineWatch.stop();
    _gradual?.interrupted();
    _interest?.interrupted();
    _live?.interrupted();
    _phase = StepPhase.changed;
    _change = event;
    _faceLost = false;
    notifyListeners();
    unawaited(_handleChange(event, flush: wasRunning));
  }

  Future<void> _handleChange(FrameSourceEvent event, {required bool flush}) async {
    await _stopPump();
    if (flush) await _flushSamples();
    _openSegment = null;
    final type = switch (event) {
      FrameSourceEvent.cameraChanged => SessionEventType.cameraChanged,
      FrameSourceEvent.orientationChanged => SessionEventType.orientationChanged,
      FrameSourceEvent.zoomChanged => SessionEventType.zoomChanged,
    };
    await _sendEvent(type);
    if (event == FrameSourceEvent.cameraChanged) await _frames.stop();
  }

  // ------------------------------------------------- segment recording

  Future<void> _openPracticeSegment(
    SessionSegmentName segment,
    StimulusLayout layout,
    int? stageIndex,
  ) async {
    final session = _session;
    if (session == null) return;
    if (!_frames.isActive && !await _startCamera()) {
      throw const ApiException('The camera is not available.');
    }
    await _repo.postLayout(session.id, segment, layout, stageIndex: stageIndex);
    await _repo.postEvent(
      session.id,
      SessionEventType.segmentStart,
      tMs: _frames.nowMs,
      payload: {
        'segment': segment.wire,
        'stage_index': ?stageIndex,
      },
    );
    _openSegment = segment;
    _faceLost = false;
    _gazeFailures = 0;
    _streamProblem = null;
    _lastFaceMs = _frames.nowMs;
    if (_phase != StepPhase.running) return;
    _startPump(_token, handler: _onStreamFrame);
  }

  Future<void> _updatePracticeLayout(
    SessionSegmentName segment,
    StimulusLayout layout,
    int? stageIndex,
  ) async {
    final session = _session;
    if (session == null || _openSegment == null) return;
    try {
      await _repo.postLayout(session.id, segment, layout, stageIndex: stageIndex);
    } catch (e) {
      _error = userMessage(e);
      notifyListeners();
    }
  }

  Future<void> _closePracticeSegment(SessionSegmentName segment) async {
    if (_openSegment == null) return;
    await _stopPump();
    await _inFlight;
    await _flushSamples();
    await _sendEvent(SessionEventType.segmentEnd,
        payload: {'segment': segment.wire});
    _openSegment = null;
  }

  // ----------------------------------------------------------- summary

  Future<void> _enterSummary() async {
    _step = SessionStep.summary;
    _phase = StepPhase.idle;
    _busy = true;
    _error = null;
    notifyListeners();
    await _frames.stop();
    if (!_ended) {
      await _sendEvent(SessionEventType.end,
          payload: {'reason': _endReason});
    }
    await _loadSummary();
    _busy = false;
    notifyListeners();
  }

  Future<void> _loadSummary() async {
    final session = _session;
    if (session == null) return;
    try {
      _summary = await _repo.summary(session.id);
    } catch (e) {
      _error = userMessage(e);
    }
  }

  /// Fetches the summary again after a failure.
  Future<void> reloadSummary() async {
    if (_busy || _step != SessionStep.summary) return;
    _busy = true;
    _error = null;
    notifyListeners();
    if (!_ended) {
      await _sendEvent(SessionEventType.end, payload: {'reason': _endReason});
    }
    await _loadSummary();
    _busy = false;
    notifyListeners();
  }

  // ----------------------------------------------------------- helpers

  bool _alive(int token) => !isDisposed && token == _token;

  void _cancelRun() {
    _token++;
    _collector = null;
    _streamHandler = null;
  }

  void _fail(int token, String message) {
    if (!_alive(token)) return;
    _error = message;
    _phase = StepPhase.idle;
    notifyListeners();
  }

  /// Sends a session event. Failures are shown, never thrown.
  Future<void> _sendEvent(
    SessionEventType type, {
    int? tMs,
    Map<String, dynamic>? payload,
  }) async {
    final session = _session;
    if (session == null) return;
    try {
      await _repo.postEvent(
        session.id,
        type,
        tMs: tMs ?? _frames.nowMs,
        payload: payload,
      );
      if (type == SessionEventType.end) _ended = true;
    } catch (e) {
      _error = userMessage(e);
      notifyListeners();
    }
  }

  // ---- capture of targets

  /// Countdown, then for each of [count] targets: settle, then capture.
  /// Returns the samples per target, or null when interrupted.
  Future<List<List<RawGazeSample>>?> _runCapture(
    int token,
    int count,
    Duration captureTime,
  ) async {
    _startPump(token);
    try {
      for (var n = timing.countdownFrom; n >= 1; n--) {
        if (!_alive(token)) return null;
        _countdown = n;
        _phase = StepPhase.countdown;
        notifyListeners();
        await Future<void>.delayed(timing.countdownStep);
      }
      final all = <List<RawGazeSample>>[];
      for (var i = 0; i < count; i++) {
        if (!_alive(token)) return null;
        _targetIndex = i;
        _stage = TargetStage.settling;
        _phase = StepPhase.capturing;
        notifyListeners();
        await Future<void>.delayed(timing.settle);
        if (!_alive(token)) return null;
        _stage = TargetStage.capturing;
        notifyListeners();
        final bucket = <RawGazeSample>[];
        _collector = bucket;
        await Future<void>.delayed(captureTime);
        _collector = null;
        await _inFlight;
        if (!_alive(token)) return null;
        all.add(bucket);
      }
      return all;
    } finally {
      await _stopPump();
    }
  }

  // ---- frame pump

  void _startPump(
    int token, {
    void Function(CapturedFrame frame, RawGazeSample? sample)? handler,
  }) {
    _frameSub?.cancel();
    _streamHandler = handler;
    final fps = math.min(timing.fps, _gazeInfo?.maxFps ?? timing.fps);
    _frameSub = _frames.frames(fps: fps).listen((frame) => _onFrame(frame, token));
  }

  Future<void> _stopPump() async {
    final sub = _frameSub;
    _frameSub = null;
    _collector = null;
    _streamHandler = null;
    await sub?.cancel();
  }

  void _onFrame(CapturedFrame frame, int token) {
    if (!_alive(token) || _estimating) return;
    final bucket = _collector;
    final handler = _streamHandler;
    if (bucket == null && handler == null) return;
    _estimating = true;
    _inFlight = _estimate(frame, token, bucket, handler);
  }

  Future<void> _estimate(
    CapturedFrame frame,
    int token,
    List<RawGazeSample>? bucket,
    void Function(CapturedFrame, RawGazeSample?)? handler,
  ) async {
    RawGazeSample? sample;
    try {
      sample = await _gaze.estimate(
        frame.jpeg,
        frame.tMs,
        frame.width,
        frame.height,
      );
      _gazeFailures = 0;
    } catch (_) {
      _gazeFailures++;
    } finally {
      _estimating = false;
    }
    if (!_alive(token)) return;
    if (sample != null) bucket?.add(sample);
    handler?.call(frame, sample);
  }

  // ---- sample upload

  List<RawGazeSample> _takePending() {
    final batch = List<RawGazeSample>.of(_pending);
    _pending.clear();
    return batch;
  }

  void _enqueuePost(List<RawGazeSample> batch) {
    final session = _session;
    if (session == null || batch.isEmpty) return;
    _postChain = (_postChain ?? Future<void>.value()).then((_) async {
      try {
        final ack = await _repo.postSamples(session.id, batch);
        _storedSamples += ack.stored;
        _invalidSamples += ack.invalid;
      } catch (e) {
        _error = userMessage(e);
        notifyListeners();
      }
    });
  }

  /// Uploads what is left and waits for every earlier upload.
  Future<void> _flushSamples() async {
    _enqueuePost(_takePending());
    await _postChain;
  }

  @override
  void dispose() {
    _token++;
    _frameSub?.cancel();
    _eventSub?.cancel();
    _gradual?.dispose();
    _interest?.cancel();
    _interest?.dispose();
    _live?.dispose();
    unawaited(_frames.stop());
    super.dispose();
  }
}

/// Lets the practice controllers open and close segments through the flow.
class _FlowRecorder implements SegmentRecorder {
  _FlowRecorder(this._flow);

  final SessionFlowController _flow;

  @override
  int get nowMs => _flow._frames.nowMs;

  @override
  Future<void> openSegment(
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  }) =>
      _flow._openPracticeSegment(segment, layout, stageIndex);

  @override
  Future<void> updateLayout(
    SessionSegmentName segment,
    StimulusLayout layout, {
    int? stageIndex,
  }) =>
      _flow._updatePracticeLayout(segment, layout, stageIndex);

  @override
  Future<void> closeSegment(SessionSegmentName segment) =>
      _flow._closePracticeSegment(segment);
}

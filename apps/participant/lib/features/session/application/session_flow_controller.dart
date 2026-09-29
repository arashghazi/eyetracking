import 'dart:async';
import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/session_repository.dart';
import '../domain/session_step.dart';
import '../domain/stimulus_geometry.dart';

/// Runs the guided session: introduction, camera check, calibration,
/// validation, baseline observation and summary.
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
  }) : _repo = repository;

  final SessionRepository _repo;
  final GazeEstimator _gaze;
  final FrameSource _frames;
  final DeviceInfo _device;
  final SessionTiming timing;

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

  double get baselineProgress {
    final total = timing.baseline.inMilliseconds;
    return total == 0 ? 1 : (_baselineElapsedMs / total).clamp(0.0, 1.0);
  }

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
          : (_step == SessionStep.baseline &&
              (_phase == StepPhase.running || _phase == StepPhase.paused));

  bool get hasActiveSession =>
      _session != null &&
      !_ended &&
      _step != SessionStep.intro &&
      _step != SessionStep.summary;

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
    } finally {
      _busy = false;
      notifyListeners();
    }
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
        ));
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
    _step = SessionStep.baseline;
    _phase = StepPhase.idle;
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------- baseline

  /// Posts the layout, opens the baseline segment and streams gaze samples
  /// for the baseline duration.
  Future<void> startBaseline() async {
    final session = _session;
    final layout = this.layout;
    if (session == null || layout == null) return;
    if (_step != SessionStep.baseline || _phase != StepPhase.idle) return;
    final token = ++_token;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (!_frames.isActive && !await _startCamera()) return;
      await _repo.postLayout(session.id, SessionSegmentName.baseline, layout);
      if (!_alive(token)) return;
      await _repo.postEvent(
        session.id,
        SessionEventType.segmentStart,
        tMs: _frames.nowMs,
        payload: {'segment': SessionSegmentName.baseline.wire},
      );
    } catch (e) {
      _error = userMessage(e);
      return;
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (!_alive(token)) return;
    _baselineElapsedMs = 0;
    _baselineWatch
      ..reset()
      ..start();
    _faceLost = false;
    _gazeFailures = 0;
    _streamProblem = null;
    _storedSamples = 0;
    _invalidSamples = 0;
    _phase = StepPhase.running;
    notifyListeners();
    unawaited(_runBaseline(token));
  }

  Future<void> _runBaseline(int token) async {
    _lastFaceMs = _frames.nowMs;
    _startPump(token, handler: (frame, sample) => _onBaselineFrame(frame, sample));
    while (_alive(token) && _baselineWatch.elapsed < timing.baseline) {
      await Future<void>.delayed(timing.progressTick);
      if (!_alive(token)) return;
      _baselineElapsedMs = _baselineWatch.elapsedMilliseconds;
      notifyListeners();
    }
    if (!_alive(token)) return;
    _baselineElapsedMs = timing.baseline.inMilliseconds;
    await _stopPump();
    await _inFlight;
    if (!_alive(token)) return;
    _baselineWatch.stop();
    await _flushSamples();
    if (!_alive(token)) return;
    await _sendEvent(SessionEventType.segmentEnd,
        payload: {'segment': SessionSegmentName.baseline.wire});
    if (!_alive(token)) return;
    await _enterSummary();
  }

  void _onBaselineFrame(CapturedFrame frame, RawGazeSample? sample) {
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

  // ------------------------------------------------------ pause / end

  /// Pauses what is running. During the baseline this sends `pause` and stops
  /// the camera; during calibration or validation it only stops locally
  /// (the server has no segment running yet).
  Future<void> pause() async {
    if (!canPause || _switching) return;
    _switching = true;
    final wasBaseline = _step == SessionStep.baseline;
    _cancelRun();
    _baselineWatch.stop();
    await _stopPump();
    _phase = StepPhase.paused;
    _faceLost = false;
    notifyListeners();
    try {
      if (wasBaseline) {
        await _flushSamples();
        await _sendEvent(SessionEventType.pause);
      }
      await _frames.stop();
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// Continues after [pause]. The baseline restarts streaming; calibration
  /// and validation return to their instructions.
  Future<void> resume() async {
    if (!canResume) return;
    _switching = true;
    try {
      if (!await _startCamera()) {
        notifyListeners();
        return;
      }
      if (_step != SessionStep.baseline) {
        _phase = StepPhase.idle;
        notifyListeners();
        return;
      }
      final token = ++_token;
      await _sendEvent(SessionEventType.resume);
      if (!_alive(token)) return;
      _baselineWatch.start();
      _phase = StepPhase.running;
      notifyListeners();
      unawaited(_runBaseline(token));
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// Ends the session early and shows the summary.
  Future<void> endEarly() async {
    if (_session == null || _ended || _step == SessionStep.summary) return;
    final wasStreaming = _step == SessionStep.baseline &&
        (_phase == StepPhase.running || _phase == StepPhase.paused);
    _cancelRun();
    _baselineWatch.stop();
    await _stopPump();
    if (wasStreaming) await _flushSamples();
    _endReason = EndReason.endedEarly;
    await _enterSummary();
  }

  // ------------------------------------------------------ device change

  void _onFrameSourceEvent(FrameSourceEvent event) {
    if (!_step.hasSessionControls || _ended || _phase == StepPhase.changed) {
      return;
    }
    final wasRunning = _step == SessionStep.baseline &&
        (_phase == StepPhase.running);
    _cancelRun();
    _baselineWatch.stop();
    _phase = StepPhase.changed;
    _change = event;
    _faceLost = false;
    notifyListeners();
    unawaited(_handleChange(event, flush: wasRunning));
  }

  Future<void> _handleChange(FrameSourceEvent event, {required bool flush}) async {
    await _stopPump();
    if (flush) await _flushSamples();
    final type = switch (event) {
      FrameSourceEvent.cameraChanged => SessionEventType.cameraChanged,
      FrameSourceEvent.orientationChanged => SessionEventType.orientationChanged,
      FrameSourceEvent.zoomChanged => SessionEventType.zoomChanged,
    };
    await _sendEvent(type);
    if (event == FrameSourceEvent.cameraChanged) await _frames.stop();
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
    unawaited(_frames.stop());
    super.dispose();
  }
}

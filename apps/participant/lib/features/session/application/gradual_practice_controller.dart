import 'dart:async';
import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/practice_trials.dart';
import '../domain/session_repository.dart';
import '../domain/session_step.dart';
import 'segment_recorder.dart';

/// What the gradual face practice is doing right now.
enum GradualPhase {
  /// Nothing has started yet.
  ready,

  /// A short blank before the first number of an attempt.
  leadIn,

  /// A number is on the screen and waits for an answer.
  trial,

  /// The pause between two numbers.
  between,

  /// The comfort question after a stage.
  comfort,

  /// Waiting for the server (trials, comfort answer, stage decision).
  posting,

  /// The server's decision is shown with a gentle message.
  decision,

  /// A request failed; [GradualPracticeController.retry] tries again.
  problem,

  /// Practice is over.
  finished,
}

/// Runs the gradual face practice: stage after stage of numbers around a face
/// that becomes more detailed, driven by the server's decision after each
/// stage. It never shows a score and never punishes a wrong answer.
///
/// The controller decides what is shown and asks a [SegmentRecorder] to open
/// and close the recorded segments; it talks to the server through the
/// [SessionRepository] (trials, comfort answer, stage result).
class GradualPracticeController extends SafeChangeNotifier {
  GradualPracticeController({
    required this.sessionId,
    required this.protocol,
    required this.layout,
    required SessionRepository repository,
    required this._recorder,
    required this.profileMode,
    this.timing = const SessionTiming(),
    this.bottomInset = 0,
    math.Random? random,
    this.onFinished,
  })  : _repo = repository,
        _random = random ?? math.Random() {
    assert(protocol.gradual != null && protocol.gradual!.stages.isNotEmpty);
  }

  final String sessionId;
  final ProtocolDefinition protocol;

  /// The face card layout; the numbers are placed relative to it. Replaced
  /// when the participant recalibrates in the middle of the practice.
  StimulusLayout layout;
  final ResponseMode profileMode;
  final SessionTiming timing;

  /// Height reserved at the bottom for the response controls.
  final double bottomInset;
  final void Function(PracticeEnd end)? onFinished;

  final SessionRepository _repo;
  final SegmentRecorder _recorder;
  final math.Random _random;

  GradualPhase _phase = GradualPhase.ready;
  int _stageIndex = 0;
  int _token = 0;

  /// Trials of the stage attempt in progress; posted in one batch.
  final List<TrialRecord> _attempt = [];
  int _trialsShown = 0;
  final Map<int, int> _trialCounter = {};
  TrialStimulus? _stimulus;
  String? _previous;
  Completer<_TrialOutcome>? _pending;
  Timer? _timeout;
  final Stopwatch _clock = Stopwatch();
  int _shownAtMs = 0;

  StageDecision? _decision;
  bool _segmentOpen = false;
  bool _started = false;
  String? _error;
  Future<void> Function()? _retryAction;
  PracticeEnd? _end;

  // ------------------------------------------------------------ getters

  GradualPhase get phase => _phase;
  int get stageIndex => _stageIndex;
  GradualConfig get config => protocol.gradual!;
  List<GradualStage> get stages => config.stages;
  GradualStage get stage => stages[_stageIndex];
  int get stageCount => stages.length;

  /// Number of the trial on the screen within this attempt (1-based).
  int get trialNumber => math.min(_trialsShown, stage.trials);
  int get trialCount => stage.trials;
  TrialStimulus? get stimulus => _stimulus;
  TrialInput get input => resolveTrialInput(stage.responseMode, profileMode);
  ComfortConfig get comfort => protocol.comfort;
  StageDecision? get decision => _decision;
  String? get error => _error;
  PracticeEnd? get end => _end;
  bool get started => _started;

  /// A friendly sentence for the decision of the last stage. Never a score.
  String get decisionMessage {
    final d = _decision;
    if (d == null) return '';
    return switch (d.kind) {
      StageDecisionKind.advance => 'Nice work. Next comes a new picture.',
      StageDecisionKind.hold => "Let's do this one again.",
      StageDecisionKind.easier =>
        "Let's go back one step to a gentler picture.",
      StageDecisionKind.stop =>
        "Let's stop here. Thank you, you did well to come this far.",
      StageDecisionKind.complete => 'You have finished the practice. Thank you.',
    };
  }

  /// Label of the button under [decisionMessage].
  String get decisionButton => switch (_decision?.kind) {
        StageDecisionKind.stop => 'Finish',
        StageDecisionKind.complete => 'Continue',
        _ => 'Continue',
      };

  // ------------------------------------------------------------ control

  /// Starts (or restarts) the current stage. Trials of an attempt that was
  /// interrupted before it finished are dropped.
  Future<void> startStage() async {
    if (_phase == GradualPhase.finished) return;
    _started = true;
    final token = ++_token;
    _attempt.clear();
    _trialsShown = 0;
    _stimulus = null;
    _decision = null;
    _error = null;
    _phase = GradualPhase.leadIn;
    notifyListeners();
    try {
      if (!_segmentOpen) {
        await _recorder.openSegment(
          SessionSegmentName.practice,
          layout,
          stageIndex: _stageIndex,
        );
        _segmentOpen = true;
      }
    } catch (e) {
      _fail(token, userMessage(e), startStage);
      return;
    }
    if (!_alive(token)) return;
    // The stage runs on its own; this call returns once it has begun.
    unawaited(_runTrials(token, leadIn: true));
  }

  Future<void> _runTrials(int token, {required bool leadIn}) async {
    if (leadIn) {
      _phase = GradualPhase.leadIn;
      notifyListeners();
      await Future<void>.delayed(timing.leadIn);
      if (!_alive(token)) return;
    }
    while (_alive(token) && _attempt.length < stage.trials) {
      _showTrial();
      final outcome = await _awaitAnswer(token);
      if (!_alive(token) || outcome == null) return;
      _record(outcome);
      _phase = GradualPhase.between;
      _stimulus = null;
      notifyListeners();
      await Future<void>.delayed(timing.interTrial);
    }
    if (!_alive(token)) return;
    await _finishStage(token);
  }

  void _showTrial() {
    final st = stage;
    final trial = buildTrial(
      stage: st,
      input: input,
      layout: layout,
      random: _random,
      previous: _previous,
      bottomInset: bottomInset,
    );
    _previous = trial.shown;
    _stimulus = trial;
    _trialsShown = _attempt.length + 1;
    _shownAtMs = _recorder.nowMs;
    _clock
      ..reset()
      ..start();
    _phase = GradualPhase.trial;
    notifyListeners();
  }

  Future<_TrialOutcome?> _awaitAnswer(int token) {
    final completer = _pending = Completer<_TrialOutcome>();
    _timeout?.cancel();
    _timeout = Timer(timing.seconds(stage.trialSeconds), () {
      if (!completer.isCompleted) completer.complete(const _TrialOutcome(null, null));
    });
    return completer.future.then((o) => _alive(token) ? o : null);
  }

  /// The participant answered the trial on the screen. An empty answer is
  /// ignored.
  void submit(String response) {
    final pending = _pending;
    final answer = response.trim();
    if (_phase != GradualPhase.trial || pending == null || pending.isCompleted) {
      return;
    }
    if (answer.isEmpty) return;
    _timeout?.cancel();
    pending.complete(_TrialOutcome(answer, _clock.elapsedMilliseconds));
  }

  void _record(_TrialOutcome outcome) {
    final trial = _stimulus!;
    final counter = _trialCounter[_stageIndex] ?? 0;
    _trialCounter[_stageIndex] = counter + 1;
    _attempt.add(TrialRecord(
      stageIndex: _stageIndex,
      trialIndex: counter,
      tMs: _shownAtMs,
      numberShown: trial.shown,
      zone: stage.numberZone.wire,
      x: trial.placement.x,
      y: trial.placement.y,
      faceLevel: stage.faceLevel,
      response: outcome.response,
      responseMs: outcome.responseMs,
    ));
  }

  Future<void> _finishStage(int token) async {
    _phase = GradualPhase.posting;
    _stimulus = null;
    notifyListeners();
    try {
      if (_segmentOpen) {
        await _recorder.closeSegment(SessionSegmentName.practice);
        _segmentOpen = false;
      }
      if (!_alive(token)) return;
      await _repo.postTrials(sessionId, List.of(_attempt));
    } catch (e) {
      _fail(token, userMessage(e), () => _finishStage(_token));
      return;
    }
    if (!_alive(token)) return;
    if (comfort.askEveryStage) {
      _phase = GradualPhase.comfort;
      notifyListeners();
    } else {
      await _requestDecision(token, null);
    }
  }

  /// The participant answered the comfort question with scale value [value].
  Future<void> answerComfort(int value) async {
    if (_phase != GradualPhase.comfort) return;
    final token = _token;
    _phase = GradualPhase.posting;
    notifyListeners();
    try {
      await _repo.postEvent(
        sessionId,
        SessionEventType.comfortAnswer,
        tMs: _recorder.nowMs,
        payload: {'value': value, 'stage_index': _stageIndex},
      );
    } catch (e) {
      _fail(token, userMessage(e), () async {
        _phase = GradualPhase.comfort;
        _error = null;
        notifyListeners();
      });
      return;
    }
    await _requestDecision(token, value);
  }

  Future<void> _requestDecision(int token, int? comfortValue) async {
    _phase = GradualPhase.posting;
    notifyListeners();
    try {
      final decision = await _repo.stageResult(
        sessionId,
        _stageIndex,
        comfortValue: comfortValue,
      );
      if (!_alive(token)) return;
      _decision = decision;
      _phase = GradualPhase.decision;
      notifyListeners();
    } catch (e) {
      _fail(token, userMessage(e), () => _requestDecision(_token, comfortValue));
    }
  }

  /// Acts on the server's decision: next stage, the same stage again, the
  /// previous stage, or the end of the practice.
  Future<void> continueAfterDecision() async {
    final d = _decision;
    if (_phase != GradualPhase.decision || d == null) return;
    switch (d.kind) {
      case StageDecisionKind.advance:
        final next = d.nextStageIndex ?? _stageIndex + 1;
        if (next >= stages.length) {
          _finish(PracticeEnd.completed);
        } else {
          _stageIndex = math.max(0, next);
          await startStage();
        }
      case StageDecisionKind.hold:
        await startStage();
      case StageDecisionKind.easier:
        _stageIndex = math.max(
          0,
          math.min(d.nextStageIndex ?? _stageIndex - 1, stages.length - 1),
        );
        await startStage();
      case StageDecisionKind.stop:
        _finish(PracticeEnd.stopped);
      case StageDecisionKind.complete:
        _finish(PracticeEnd.completed);
    }
  }

  void _finish(PracticeEnd end) {
    _token++;
    _end = end;
    _phase = GradualPhase.finished;
    notifyListeners();
    onFinished?.call(end);
  }

  /// The participant would rather not answer the comfort question: the stage
  /// result is requested without a comfort value.
  Future<void> skipComfort() async {
    if (_phase != GradualPhase.comfort) return;
    await _requestDecision(_token, null);
  }

  /// The camera or screen changed: the segment on the server is closed and
  /// the clock stops. [resumeAfterInterruption] continues.
  void interrupted() {
    pause();
    _segmentOpen = false;
  }

  /// Continues after a recalibration: an interrupted stage starts again from
  /// its first number; a question, decision or error screen simply returns.
  Future<void> resumeAfterInterruption() async {
    _segmentOpen = false;
    final running = _phase == GradualPhase.leadIn ||
        _phase == GradualPhase.trial ||
        _phase == GradualPhase.between ||
        _phase == GradualPhase.ready;
    if (running) {
      await startStage();
    } else {
      notifyListeners();
    }
  }

  /// Tries the failed request again.
  Future<void> retry() async {
    final action = _retryAction;
    if (_phase != GradualPhase.problem || action == null) return;
    _error = null;
    _retryAction = null;
    await action();
  }

  // ------------------------------------------------------ pause / cancel

  /// Stops the clock. A number that is on the screen is dropped and shown
  /// again (as a new one) after [resume].
  void pause() {
    final running = _phase == GradualPhase.leadIn ||
        _phase == GradualPhase.trial ||
        _phase == GradualPhase.between;
    // A request in flight (posting, comfort, decision) finishes on its own.
    if (!running) return;
    _token++;
    _timeout?.cancel();
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const _TrialOutcome(null, null));
    }
    _pending = null;
    _stimulus = null;
    notifyListeners();
  }

  /// Continues after [pause]. Question, decision and error screens simply
  /// come back; a stage in progress carries on with its next number.
  void resume() {
    if (_phase == GradualPhase.trial ||
        _phase == GradualPhase.between ||
        _phase == GradualPhase.leadIn) {
      final token = ++_token;
      unawaited(_runTrials(token, leadIn: true));
    } else {
      notifyListeners();
    }
  }

  /// Ends everything without a result (the session ended or the screen closed).
  void cancel() {
    _token++;
    _timeout?.cancel();
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const _TrialOutcome(null, null));
    }
    _pending = null;
  }

  // ------------------------------------------------------------ helpers

  bool _alive(int token) => !isDisposed && token == _token;

  void _fail(int token, String message, Future<void> Function() retry) {
    if (!_alive(token)) return;
    _error = message;
    _retryAction = retry;
    _phase = GradualPhase.problem;
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

class _TrialOutcome {
  const _TrialOutcome(this.response, this.responseMs);

  final String? response;
  final int? responseMs;
}

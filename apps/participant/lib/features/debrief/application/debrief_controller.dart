import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/debrief_models.dart';
import '../domain/debrief_repository.dart';

/// Where the optional debrief card of one session stands.
enum DebriefPhase {
  /// Asking the server whether there is anything to ask.
  loading,

  /// Nothing to show: the debrief is off, the session is not ended, it was
  /// answered before, or the form could not be loaded.
  hidden,

  /// The questions are on the screen.
  asking,

  /// The participant sent answers or skipped. Never asked again.
  thanked,
}

/// Drives "A few questions about this session": loads the form, holds the
/// answers while they are typed, sends them or a skip, and keeps the server's
/// message when it refuses. One instance per session summary.
class DebriefController extends SafeChangeNotifier {
  DebriefController({
    required DebriefRepository repository,
    required this.sessionId,
  }) : _repo = repository;

  final DebriefRepository _repo;
  final String sessionId;

  DebriefPhase _phase = DebriefPhase.loading;
  ParticipantDebriefForm? _form;
  final Map<String, Object> _answers = {};
  bool _busy = false;
  String? _error;
  bool _needsReload = false;
  bool _skipped = false;

  DebriefPhase get phase => _phase;
  ParticipantDebriefForm? get form => _form;
  bool get busy => _busy;

  /// The server's message for the last refusal, as written.
  String? get error => _error;

  /// The last refusal was a 409: the questions or the session changed, and
  /// the participant should reload the questions.
  bool get needsReload => _needsReload;

  /// The participant chose to skip (shown in the thank-you line).
  bool get skipped => _skipped;

  /// The value given to [key], or null.
  Object? answerFor(String key) => _answers[key];

  /// Every required question has a valid answer.
  bool get requiredAnswered {
    final form = _form;
    if (form == null) return false;
    return form.questions
        .where((q) => q.required)
        .every((q) => q.accepts(_answers[q.key]));
  }

  bool get canSubmit =>
      _phase == DebriefPhase.asking && !_busy && requiredAnswered;

  bool get canSkip => _phase == DebriefPhase.asking && !_busy;

  /// Asks the server for the form. A failure hides the card: the questions
  /// are optional and must never get in the way of the summary.
  Future<void> load() async {
    _phase = DebriefPhase.loading;
    notifyListeners();
    await _fetch(keepAnswers: false);
  }

  /// Loads the questions again after a 409, keeping the answers that still
  /// fit the new form.
  Future<void> reload() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _needsReload = false;
    notifyListeners();
    await _fetch(keepAnswers: true);
    _busy = false;
    notifyListeners();
  }

  Future<void> _fetch({required bool keepAnswers}) async {
    final SessionDebrief state;
    try {
      state = await _repo.load(sessionId);
    } catch (e) {
      if (keepAnswers && _phase == DebriefPhase.asking) {
        _error = userMessage(e);
        _needsReload = true;
      } else {
        _phase = DebriefPhase.hidden;
      }
      notifyListeners();
      return;
    }
    if (!state.shouldAsk) {
      _phase = DebriefPhase.hidden;
      _form = null;
      _answers.clear();
    } else {
      final form = state.form!;
      final kept = keepAnswers
          ? {
              for (final q in form.questions)
                if (_answers[q.key] case final Object v when q.accepts(v))
                  q.key: v,
            }
          : <String, Object>{};
      _answers
        ..clear()
        ..addAll(kept);
      _form = form;
      _phase = DebriefPhase.asking;
    }
    notifyListeners();
  }

  /// Sets or, with null, clears the answer to [key]. Values that do not fit
  /// the question are ignored.
  void setAnswer(String key, Object? value) {
    if (_phase != DebriefPhase.asking || _busy) return;
    final question = _question(key);
    if (question == null) return;
    if (value == null || (value is String && value.trim().isEmpty)) {
      if (_answers.remove(key) == null) return;
    } else if (question.accepts(value)) {
      if (_answers[key] == value) return;
      _answers[key] = value;
    } else {
      return;
    }
    notifyListeners();
  }

  ParticipantDebriefQuestion? _question(String key) {
    for (final q in _form?.questions ?? const <ParticipantDebriefQuestion>[]) {
      if (q.key == key) return q;
    }
    return null;
  }

  void dismissError() {
    if (_error == null) return;
    _error = null;
    _needsReload = false;
    notifyListeners();
  }

  /// Sends the answers; enabled only when every required question has one.
  Future<bool> submit() =>
      canSubmit ? _send(skipped: false) : Future.value(false);

  /// Tells the server the participant skipped the questions.
  Future<bool> skip() => canSkip ? _send(skipped: true) : Future.value(false);

  Future<bool> _send({required bool skipped}) async {
    final form = _form!;
    _busy = true;
    _error = null;
    _needsReload = false;
    notifyListeners();
    final answer = DebriefAnswer(
      formVersion: form.version,
      skipped: skipped,
      answers: skipped
          ? const {}
          : {
              for (final q in form.questions)
                if (q.accepts(_answers[q.key]))
                  q.key: _sendValue(_answers[q.key]!),
            },
    );
    try {
      await _repo.submit(sessionId, answer);
      _phase = DebriefPhase.thanked;
      _skipped = skipped;
      return true;
    } catch (e) {
      _error = userMessage(e);
      _needsReload = e is ApiException && e.statusCode == 409;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Text is sent without the spaces around it.
  static Object _sendValue(Object value) =>
      value is String ? value.trim() : value;
}

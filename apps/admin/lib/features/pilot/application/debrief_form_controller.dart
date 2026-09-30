import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/pilot_repository.dart';
import 'number_input.dart';

/// One question as the editor holds it: plain text the person is typing, not
/// yet checked. [uid] keeps the editor's fields with their question when the
/// list is reordered.
class DebriefDraft {
  DebriefDraft({
    required this.uid,
    this.key = '',
    this.type = DebriefQuestionType.text,
    this.prompt = '',
    this.required = false,
    this.scaleMax = '5',
    this.labelsText = '',
    this.optionsText = '',
  });

  factory DebriefDraft.from(DebriefQuestion q, int uid) => DebriefDraft(
        uid: uid,
        key: q.key,
        type: q.type,
        prompt: q.prompt,
        required: q.required,
        scaleMax: '${q.scaleMax ?? 5}',
        labelsText: q.labels.join('\n'),
        optionsText: q.options.join('\n'),
      );

  final int uid;
  String key;
  String type;
  String prompt;
  bool required;
  String scaleMax;

  /// One label per line (scale questions).
  String labelsText;

  /// One option per line (choice questions).
  String optionsText;

  static List<String> _lines(String text) => [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];

  List<String> get labels => _lines(labelsText);
  List<String> get options => _lines(optionsText);

  DebriefQuestion toQuestion() => DebriefQuestion(
        key: key.trim(),
        type: type,
        prompt: prompt.trim(),
        required: required,
        scaleMax: type == DebriefQuestionType.scale
            ? (parseWhole(scaleMax) ?? 0)
            : null,
        labels: type == DebriefQuestionType.scale ? labels : const [],
        options: type == DebriefQuestionType.choice ? options : const [],
      );
}

/// The Questions-after-a-session section: the short, versioned form a
/// participant may answer when a session has ended.
///
/// Changed questions make a new version and answers already given keep the
/// version they were answered for. The on/off switch alone does not create a
/// version. Researchers edit; analysts read.
class DebriefFormController extends SafeChangeNotifier {
  DebriefFormController(this._repository, this.studyId, {required this.canEdit});

  final PilotRepository _repository;
  final int studyId;
  final bool canEdit;

  DebriefForm? _form;
  List<DebriefDraft> _drafts = const [];
  bool _enabled = false;
  int _nextUid = 1;
  Map<int, String> _problems = const {};
  String? _listProblem;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _notice;

  DebriefForm? get form => _form;
  List<DebriefDraft> get drafts => _drafts;
  bool get enabled => _enabled;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  String? get notice => _notice;

  /// Why the list as a whole is not acceptable (too many or no questions).
  String? get listProblem => _listProblem;
  String? problemFor(int uid) => _problems[uid];

  /// 0 until the first save.
  int get version => _form?.version ?? 0;
  bool get saved => _form?.saved ?? false;
  bool get canAdd => _drafts.length < DebriefQuestion.maxQuestions;

  /// The questions differ from the saved ones.
  bool get questionsChanged {
    final form = _form;
    if (form == null) return false;
    return jsonEncode([for (final d in _drafts) d.toQuestion().toJson()]) !=
        jsonEncode([for (final q in form.questions) q.toJson()]);
  }

  bool get enabledChanged => _form != null && _enabled != _form!.enabled;
  bool get dirty => questionsChanged || enabledChanged;

  /// Nothing to save when nothing changed, except the first save (which
  /// stores the suggested questions as version 1).
  bool get canSave => canEdit && !_saving && _form != null && (dirty || !saved);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _apply(await _repository.debriefForm(studyId));
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _apply(DebriefForm form) {
    _form = form;
    _enabled = form.enabled;
    _drafts = [for (final q in form.questions) DebriefDraft.from(q, _nextUid++)];
    _problems = const {};
    _listProblem = null;
  }

  // -------------------------------------------------------------- editing

  void setEnabled(bool value) {
    _enabled = value;
    _notice = null;
    notifyListeners();
  }

  void edit(DebriefDraft draft, void Function(DebriefDraft) change) {
    change(draft);
    _problems = {..._problems}..remove(draft.uid);
    _notice = null;
    notifyListeners();
  }

  /// Adds an empty free-text question with a key nobody uses yet.
  void add() {
    if (!canAdd) return;
    final used = {for (final d in _drafts) d.key.trim()};
    var n = _drafts.length + 1;
    while (used.contains('question_$n')) {
      n++;
    }
    _drafts = [..._drafts, DebriefDraft(uid: _nextUid++, key: 'question_$n')];
    _notice = null;
    notifyListeners();
  }

  void remove(DebriefDraft draft) {
    _drafts = [
      for (final d in _drafts)
        if (d.uid != draft.uid) d,
    ];
    _problems = {..._problems}..remove(draft.uid);
    _notice = null;
    notifyListeners();
  }

  /// Moves a question up (`-1`) or down (`1`).
  void move(DebriefDraft draft, int delta) {
    final from = _drafts.indexWhere((d) => d.uid == draft.uid);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _drafts.length) return;
    final next = [..._drafts];
    next.insert(to, next.removeAt(from));
    _drafts = next;
    _notice = null;
    notifyListeners();
  }

  // --------------------------------------------------------------- saving

  /// Checks the questions the way the server does; sets the messages.
  bool _check() {
    final problems = <int, String>{};
    String? listProblem;
    if (_drafts.isEmpty || _drafts.length > DebriefQuestion.maxQuestions) {
      listProblem =
          'A form needs 1 to ${DebriefQuestion.maxQuestions} questions.';
    }
    final seen = <String>{};
    for (final d in _drafts) {
      final q = d.toQuestion();
      String? problem;
      if (!DebriefQuestion.keyPattern.hasMatch(q.key)) {
        problem = 'The key starts with a letter and uses a-z, 0-9 or _ '
            '(at most 40 characters).';
      } else if (!seen.add(q.key)) {
        problem = 'The key "${q.key}" is used twice.';
      } else if (q.prompt.isEmpty ||
          q.prompt.length > DebriefQuestion.maxPromptChars) {
        problem = 'The prompt is required (at most '
            '${DebriefQuestion.maxPromptChars} characters).';
      } else if (q.type == DebriefQuestionType.scale) {
        final max = q.scaleMax ?? 0;
        if (max < DebriefQuestion.minScaleMax || max > DebriefQuestion.maxScaleMax) {
          problem = 'The scale goes from 2 to 10 points.';
        } else if (q.labels.isNotEmpty && q.labels.length != max) {
          problem = 'Give one label per point ($max) or none.';
        }
      } else if (q.type == DebriefQuestionType.choice) {
        if (q.options.length < DebriefQuestion.minOptions ||
            q.options.length > DebriefQuestion.maxOptions) {
          problem = 'A choice needs 2 to 10 options, one per line.';
        } else if (q.options.toSet().length != q.options.length) {
          problem = 'The options must be different.';
        }
      }
      if (problem != null) problems[d.uid] = problem;
    }
    _problems = problems;
    _listProblem = listProblem;
    return problems.isEmpty && listProblem == null;
  }

  Future<bool> save() async {
    if (!canSave) return false;
    _error = null;
    _notice = null;
    final changed = questionsChanged;
    if (changed && !_check()) {
      _error = 'Some questions are not valid. Fix the marked ones and save again.';
      notifyListeners();
      return false;
    }
    _saving = true;
    notifyListeners();
    final before = version;
    final wasEnabled = _form?.enabled ?? false;
    try {
      final saved = await _repository.saveDebriefForm(
        studyId,
        questions: changed || !this.saved
            ? [for (final d in _drafts) d.toQuestion()]
            : null,
        enabled: _enabled,
      );
      _apply(saved);
      if (saved.version > before) {
        _notice = 'Saved as version ${saved.version}. Answers already given '
            'keep the version they were answered for.';
      } else if (saved.enabled != wasEnabled) {
        _notice = saved.enabled
            ? 'Participants are now asked these questions after a session.'
            : 'Participants are no longer asked these questions.';
      } else {
        _notice = 'Saved. The questions did not change, so there is no new version.';
      }
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Puts the editor back to the saved form.
  void discard() {
    final form = _form;
    if (form == null) return;
    _apply(form);
    _notice = null;
    _error = null;
    notifyListeners();
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }
}

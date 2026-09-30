import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../../content/domain/content_repository.dart';
import '../domain/ai_repository.dart';

/// The AI tab: provider status, budget and the jobs table.
///
/// While a job is queued or running the jobs are read again every
/// [pollInterval]. The timer is one-shot and re-armed after each read, and it
/// comes from [schedule] so tests can fire it by hand.
class AiController extends SafeChangeNotifier {
  AiController(
    this._repository,
    this.studyId, {
    this.content,
    Timer Function(Duration, void Function())? schedule,
    this.pollInterval = const Duration(seconds: 5),
  }) : _schedule = schedule ?? Timer.new;

  final AiRepository _repository;

  /// Only used to show content titles next to their ids.
  final ContentRepository? content;
  final int studyId;
  final Duration pollInterval;
  final Timer Function(Duration, void Function()) _schedule;

  AiStatus? _status;
  List<AiJob> _jobs = const [];
  Map<String, String> _titles = const {};
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  bool _refreshing = false;
  String? _error;
  String? _notice;
  String? _budgetError;
  AiBudget? _savedBudget;
  AiRunResult? _lastRun;
  Timer? _timer;

  AiStatus? get status => _status;
  List<AiJob> get jobs => _jobs;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  bool get busy => _busy;
  String? get error => _error;
  String? get notice => _notice;

  /// The server's refusal of the last cap change, verbatim.
  String? get budgetError => _budgetError;

  /// The budget the server answered with after the last accepted change.
  AiBudget? get savedBudget => _savedBudget;
  AiRunResult? get lastRun => _lastRun;

  bool get hasActiveJobs => _jobs.any((j) => j.isActive);

  /// A refresh is scheduled (some job is queued or running).
  bool get autoRefreshing => _timer != null;

  /// Title of a content item, when the content list knows it.
  String? contentTitle(String? contentId) =>
      contentId == null ? null : _titles[contentId];

  // ------------------------------------------------------------ loading

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _status = await _repository.status(studyId);
      _jobs = await _repository.jobs(studyId);
      _loadedOnce = true;
      await _loadTitles();
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      _syncTimer();
      notifyListeners();
    }
  }

  /// Reads status and jobs again without the loading state (polling, and
  /// when the tab comes back into view).
  Future<void> refresh() async {
    if (_refreshing || _loading || isDisposed) return;
    _refreshing = true;
    try {
      _status = await _repository.status(studyId);
      _jobs = await _repository.jobs(studyId);
      _loadedOnce = true;
      _error = null;
      await _loadTitles(onlyIfUnknown: true);
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _refreshing = false;
      _syncTimer();
      notifyListeners();
    }
  }

  Future<void> _loadTitles({bool onlyIfUnknown = false}) async {
    final content = this.content;
    if (content == null) return;
    if (onlyIfUnknown &&
        _jobs.every((j) => j.contentId == null || _titles.containsKey(j.contentId))) {
      return;
    }
    try {
      _titles = {
        for (final c in await content.list(studyId)) c.id: c.title,
      };
    } catch (_) {
      // Titles are a convenience; the id is shown without them.
    }
  }

  void _syncTimer() {
    if (isDisposed) return;
    if (!hasActiveJobs) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _timer = _schedule(pollInterval, () {
      _timer = null;
      unawaited(refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  // ------------------------------------------------------------ actions

  /// Puts a job the form or the editor just created at the top of the table.
  void addJobs(List<AiJob> created) {
    final ids = {for (final j in created) j.id};
    _jobs = [
      ...created.reversed,
      for (final j in _jobs)
        if (!ids.contains(j.id)) j,
    ];
    _notice = null;
    _syncTimer();
    notifyListeners();
    // The new job's content title is not known yet.
    unawaited(_loadTitles(onlyIfUnknown: true).then((_) => notifyListeners()));
  }

  /// Sets the cap from the text the administrator typed. Returns whether the
  /// server accepted it; a refusal is kept in [budgetError].
  Future<bool> setBudgetCap(String text) async {
    _budgetError = null;
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || value.isNaN || value.isInfinite || value < 0) {
      _budgetError = 'Enter the cap as a number of units, 0 or more.';
      notifyListeners();
      return false;
    }
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      final budget = await _repository.setBudget(studyId, value);
      // Without a readable status (an administrator who is not a member)
      // there is nothing to update; the notice carries the new cap.
      _status = _status?.copyWith(budget: budget);
      _savedBudget = budget;
      _notice = 'Cost cap saved: ${formatUnits(budget.costCapUnits)} units.';
      return true;
    } catch (e) {
      _budgetError = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Switches the free-text setting (administrators). The server's answer is
  /// what the switch then shows; a refusal is kept in [budgetError].
  Future<bool> setSendFreeText(bool value) async {
    if (_busy) return false;
    _budgetError = null;
    _notice = null;
    _busy = true;
    notifyListeners();
    try {
      final stored = await _repository.setSendFreeText(studyId, value);
      _status = _status?.copyWith(sendFreeText: stored);
      _notice = stored
          ? 'Free text is now sent to the text provider.'
          : 'Free text is no longer sent to the text provider.';
      return true;
    } catch (e) {
      _budgetError = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearBudgetError() {
    _budgetError = null;
    notifyListeners();
  }

  Future<void> cancel(AiJob job) => _jobAction(
        () => _repository.cancel(studyId, job.id),
        'Job ${job.id} cancelled.',
      );

  Future<void> retry(AiJob job) => _jobAction(
        () => _repository.retry(studyId, job.id),
        'Job ${job.id} queued again.',
      );

  Future<void> _jobAction(Future<AiJob> Function() action, String notice) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final updated = await action();
      _jobs = [
        for (final j in _jobs) j.id == updated.id ? updated : j,
      ];
      _notice = notice;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _busy = false;
      _syncTimer();
      notifyListeners();
    }
  }

  /// "Run queued jobs now".
  Future<void> runQueued() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    _lastRun = null;
    notifyListeners();
    try {
      _lastRun = await _repository.run(studyId);
      _jobs = await _repository.jobs(studyId);
      _status = await _repository.status(studyId);
      await _loadTitles(onlyIfUnknown: true);
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _busy = false;
      _syncTimer();
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    _lastRun = null;
    notifyListeners();
  }
}

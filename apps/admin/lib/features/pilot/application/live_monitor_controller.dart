import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/pilot_repository.dart';

/// The Live section: the sessions that are running now and, for the one the
/// supervisor picks, a status that is read again every [pollInterval].
///
/// The first read sends `first=true` (the server logs the start of a
/// monitoring); later reads do not. The timer is one-shot and re-armed after
/// each read finished, so reads never overlap, and it comes from [schedule]
/// so tests can fire it by hand. Polling stops when the panel is closed, the
/// section is left ([suspend]) or the session ends.
class LiveMonitorController extends SafeChangeNotifier {
  LiveMonitorController(
    this._repository,
    this.studyId, {
    Timer Function(Duration, void Function())? schedule,
    this.pollInterval = const Duration(milliseconds: 2500),
  }) : _schedule = schedule ?? Timer.new;

  final PilotRepository _repository;
  final int studyId;
  final Duration pollInterval;
  final Timer Function(Duration, void Function()) _schedule;

  List<ActiveSession> _active = const [];
  bool _activeLoading = false;
  bool _activeLoaded = false;
  String? _activeError;

  String? _selectedId;
  LiveStatus? _live;
  String? _liveError;
  bool _needsFirst = true;
  bool _monitoring = false;
  bool _suspended = false;
  bool _fetching = false;
  int _generation = 0;
  Timer? _timer;

  List<ActiveSession> get active => _active;
  bool get activeLoading => _activeLoading;
  bool get activeLoaded => _activeLoaded;
  String? get activeError => _activeError;

  /// The session whose panel is open, or null.
  String? get selectedId => _selectedId;
  ActiveSession? get selected {
    for (final s in _active) {
      if (s.sessionId == _selectedId) return s;
    }
    return null;
  }

  LiveStatus? get live => _live;
  String? get liveError => _liveError;

  /// A read is scheduled or running: the panel is being kept up to date.
  bool get polling => _monitoring && !_suspended;

  /// The session has ended; the last status stays on screen.
  bool get ended => _live?.isEnded ?? false;

  Future<void> loadActive() async {
    if (_activeLoading) return;
    _activeLoading = true;
    _activeError = null;
    notifyListeners();
    try {
      _active = await _repository.activeSessions(studyId);
      _activeLoaded = true;
    } catch (e) {
      _activeError = userMessage(e);
    } finally {
      _activeLoading = false;
      notifyListeners();
    }
  }

  /// Opens the panel of [sessionId] and starts polling.
  Future<void> select(String sessionId) async {
    _cancelTimer();
    final generation = ++_generation;
    _selectedId = sessionId;
    _live = null;
    _liveError = null;
    _needsFirst = true;
    _monitoring = true;
    _suspended = false;
    notifyListeners();
    await _poll(generation);
  }

  /// Closes the panel and stops polling.
  void close() {
    _cancelTimer();
    _generation++;
    _selectedId = null;
    _live = null;
    _liveError = null;
    _monitoring = false;
    _fetching = false;
    notifyListeners();
  }

  /// Stops polling while the section is out of view; the panel stays.
  void suspend() {
    _suspended = true;
    _cancelTimer();
    notifyListeners();
  }

  /// Reads at once and keeps polling, after [suspend].
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    notifyListeners();
    if (_monitoring && _selectedId != null && !_fetching) {
      unawaited(_poll(_generation));
    }
  }

  Future<void> _poll(int generation) async {
    final id = _selectedId;
    if (id == null || generation != _generation || isDisposed) return;
    _fetching = true;
    try {
      final status = await _repository.live(studyId, id, first: _needsFirst);
      if (generation != _generation) return;
      _needsFirst = false;
      _live = status;
      _liveError = null;
      if (status.isEnded) _monitoring = false;
    } catch (e) {
      if (generation != _generation) return;
      _liveError = userMessage(e);
      // A refusal or a missing session will not fix itself.
      if (e is ApiException && (e.isForbidden || e.isNotFound || e.isUnauthorized)) {
        _monitoring = false;
      }
    } finally {
      if (generation == _generation) {
        _fetching = false;
        notifyListeners();
        _arm(generation);
      }
    }
  }

  void _arm(int generation) {
    if (!_monitoring || _suspended || isDisposed || _timer != null) return;
    _timer = _schedule(pollInterval, () {
      _timer = null;
      if (generation == _generation) unawaited(_poll(generation));
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}

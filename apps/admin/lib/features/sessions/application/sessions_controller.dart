import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/sessions_repository.dart';

/// The Sessions tab: every session of one study.
class SessionsController extends SafeChangeNotifier {
  SessionsController(this._repository, this.studyId);

  final SessionsRepository _repository;
  final int studyId;

  List<SessionListItem> _items = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<SessionListItem> get items => _items;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repository.list(studyId);
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }
}

/// One session with its stored samples.
class SessionDetailController extends SafeChangeNotifier {
  SessionDetailController(this._repository, this.studyId, this.sessionId);

  /// Samples are fetched in pages of this size.
  static const pageSize = 100;

  /// The table shows at most this many rows (the replay and the CSV have all).
  static const displayLimit = 200;

  final SessionsRepository _repository;
  final int studyId;
  final String sessionId;

  SessionDetail? _detail;
  bool _loading = false;
  String? _error;

  int? _samplesTotal;
  List<SampleRow> _rows = const [];
  bool _samplesLoading = false;
  bool _samplesLoaded = false;

  SessionDetail? get detail => _detail;
  bool get loading => _loading;
  String? get error => _error;

  /// Total number of stored samples, once known.
  int? get samplesTotal => _samplesTotal;
  List<SampleRow> get rows => _rows;
  bool get samplesLoading => _samplesLoading;
  bool get samplesLoaded => _samplesLoaded;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _detail = await _repository.detail(studyId, sessionId);
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
    if (_detail == null) return;
    // A one-row page tells us how many samples exist without loading them.
    try {
      final page =
          await _repository.samples(studyId, sessionId, offset: 0, limit: 1);
      _samplesTotal = page.total;
      notifyListeners();
    } catch (_) {
      // The count is a convenience; the button still works.
    }
  }

  /// Pages through the samples until [displayLimit] rows are held.
  Future<void> loadSamples() async {
    if (_samplesLoading) return;
    _samplesLoading = true;
    _error = null;
    notifyListeners();
    final rows = <SampleRow>[];
    try {
      var offset = 0;
      while (rows.length < displayLimit) {
        final page = await _repository.samples(
          studyId,
          sessionId,
          offset: offset,
          limit: math.min(pageSize, displayLimit - rows.length),
        );
        _samplesTotal = page.total;
        rows.addAll(page.items);
        offset += page.items.length;
        if (page.items.isEmpty || offset >= page.total) break;
      }
      _rows = rows;
      _samplesLoaded = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _samplesLoading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }
}

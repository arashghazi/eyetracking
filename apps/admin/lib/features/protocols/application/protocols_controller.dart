import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/protocols_repository.dart';

/// The Protocols tab: every protocol of one study.
class ProtocolsController extends SafeChangeNotifier {
  ProtocolsController(this._repository, this.studyId);

  final ProtocolsRepository _repository;
  final int studyId;

  List<ProtocolSummary> _items = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  String? _error;

  List<ProtocolSummary> get items => _items;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  bool get busy => _busy;
  String? get error => _error;

  /// Published versions, the ones that can be assigned.
  List<ProtocolSummary> get published => [
        for (final p in _items)
          if (p.isPublished) p,
      ];

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

  /// Copies a published version into a new draft; returns it, or null.
  Future<ProtocolDetail?> newDraftFrom(ProtocolSummary published) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final draft = await _repository.newDraft(studyId, published.id);
      await _reloadQuietly();
      return draft;
    } catch (e) {
      _error = userMessage(e);
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _reloadQuietly() async {
    try {
      _items = await _repository.list(studyId);
    } catch (_) {
      // The list refreshes on the next visit.
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }
}

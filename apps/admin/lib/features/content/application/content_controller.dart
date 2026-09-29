import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/content_repository.dart';

/// The Content tab: every content item of one study.
class ContentController extends SafeChangeNotifier {
  ContentController(this._repository, this.studyId);

  final ContentRepository _repository;
  final int studyId;

  List<ContentSummary> _items = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<ContentSummary> get items => _items;
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

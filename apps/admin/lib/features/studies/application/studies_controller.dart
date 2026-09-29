import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/studies_repository.dart';
import '../domain/study.dart';

class StudiesController extends SafeChangeNotifier {
  StudiesController(this._repository);

  final StudiesRepository _repository;

  List<Study> _studies = const [];
  bool _loading = false;
  bool _creating = false;
  bool _loadedOnce = false;
  String? _error;
  String? _notice;

  List<Study> get studies => _studies;
  bool get loading => _loading;
  bool get creating => _creating;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;
  String? get notice => _notice;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _studies = await _repository.list();
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _error = 'Enter a name for the study.';
      notifyListeners();
      return false;
    }
    _creating = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final study = await _repository.create(trimmed);
      _studies = [..._studies, study];
      _notice = 'Study "${study.name}" created.';
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _creating = false;
      notifyListeners();
    }
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

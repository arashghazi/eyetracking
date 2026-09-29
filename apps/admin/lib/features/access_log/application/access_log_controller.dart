import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/access_log_repository.dart';

/// The Access log tab: who did what with the study's data.
class AccessLogController extends SafeChangeNotifier {
  AccessLogController(this._repository, this.studyId, {this.limit = 200});

  final AccessLogRepository _repository;
  final int studyId;
  final int limit;

  List<AccessLogEntry> _entries = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<AccessLogEntry> get entries => _entries;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _entries = await _repository.list(studyId, limit: limit);
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

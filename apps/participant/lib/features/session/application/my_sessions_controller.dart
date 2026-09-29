import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/session_repository.dart';

/// The participant's past sessions for the home screen.
class MySessionsController extends SafeChangeNotifier {
  MySessionsController(this._repository);

  final SessionRepository _repository;

  List<SessionSummary> _sessions = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<SessionSummary> get sessions => _sessions;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await _repository.mine();
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

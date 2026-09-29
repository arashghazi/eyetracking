import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/assignments_repository.dart';

/// The participant's assignments for the home screen: "Your next session".
class AssignmentsController extends SafeChangeNotifier {
  AssignmentsController(this._repository);

  final AssignmentsRepository _repository;

  List<Assignment> _all = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  /// Assignments in the server's order; cancelled ones are left out.
  List<Assignment> get assignments => [
        for (final a in _all)
          if (a.status != AssignmentStatus.cancelled) a,
      ];
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final list = await _repository.list();
      // Stable by the server's order_index; ties keep the server's order.
      final indexed = list.indexed.toList()
        ..sort((a, b) {
          final byOrder = a.$2.orderIndex.compareTo(b.$2.orderIndex);
          return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
        });
      _all = [for (final e in indexed) e.$2];
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

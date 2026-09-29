import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/data_export_repository.dart';

class DataExportController extends SafeChangeNotifier {
  DataExportController(this._repository);

  final DataExportRepository _repository;

  String? _json;
  bool _loading = false;
  String? _error;

  /// The export as indented JSON text, once loaded.
  String? get json => _json;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _repository.fetchMyData();
      _json = const JsonEncoder.withIndent('  ').convert(data);
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

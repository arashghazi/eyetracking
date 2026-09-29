import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/data_export_repository.dart';

class ApiDataExportRepository implements DataExportRepository {
  ApiDataExportRepository(this._api);

  final ApiClient _api;

  @override
  Future<Object?> fetchMyData() => _api.get('/me/data');
}

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/access_log_repository.dart';

class ApiAccessLogRepository implements AccessLogRepository {
  ApiAccessLogRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AccessLogEntry>> list(int studyId, {int limit = 200}) async => [
        for (final e
            in await _api.getList('/studies/$studyId/access-log?limit=$limit'))
          if (e is Map<String, dynamic>) AccessLogEntry.fromJson(e),
      ];
}

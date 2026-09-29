import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/analysis_filters.dart';
import '../domain/analysis_repository.dart';

class ApiAnalysisRepository implements AnalysisRepository {
  ApiAnalysisRepository(this._api);

  final ApiClient _api;

  @override
  Future<AnalysisResponse> analysis(
    int studyId,
    AnalysisFilters filters,
  ) async =>
      AnalysisResponse.fromJson(
        await _api.getObject('/studies/$studyId/analysis?${filters.queryString}'),
      );
}

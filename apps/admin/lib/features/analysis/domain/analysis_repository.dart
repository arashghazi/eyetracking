import 'package:eyetracking_core/eyetracking_core.dart';

import 'analysis_filters.dart';

/// Read access to the analysis view of a study (researchers and analysts).
abstract class AnalysisRepository {
  Future<AnalysisResponse> analysis(int studyId, AnalysisFilters filters);
}

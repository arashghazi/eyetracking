import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../../analysis/domain/analysis_filters.dart';

/// Files a researcher or analyst can download (every download is written to
/// the study's access log by the server).
abstract class ExportsRepository {
  /// One row per session, same filters as the analysis.
  Future<Uint8List> sessionsCsv(int studyId, AnalysisFilters filters);

  Future<Uint8List> sessionsJson(int studyId, AnalysisFilters filters);

  /// `t_ms,x,y,conf,valid,region,segment,layout_id` of one session.
  Future<Uint8List> samplesCsv(int studyId, String sessionId);

  /// `t_ms,type,payload_json` of one session.
  Future<Uint8List> eventsCsv(int studyId, String sessionId);

  /// What every exported column and summary field means.
  Future<List<DictionaryEntry>> dataDictionary(int studyId);
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../../analysis/domain/analysis_filters.dart';
import '../domain/exports_repository.dart';

class ApiExportsRepository implements ExportsRepository {
  ApiExportsRepository(this._api);

  final ApiClient _api;

  String _base(int studyId) => '/studies/$studyId/exports';

  @override
  Future<Uint8List> sessionsCsv(int studyId, AnalysisFilters filters) =>
      _api.getBytes('${_base(studyId)}/sessions.csv?${filters.queryString}');

  @override
  Future<Uint8List> sessionsJson(int studyId, AnalysisFilters filters) =>
      _api.getBytes('${_base(studyId)}/sessions.json?${filters.queryString}');

  @override
  Future<Uint8List> samplesCsv(int studyId, String sessionId) => _api.getBytes(
      '${_base(studyId)}/samples.csv?session_id=${Uri.encodeQueryComponent(sessionId)}');

  @override
  Future<Uint8List> eventsCsv(int studyId, String sessionId) => _api.getBytes(
      '${_base(studyId)}/events.csv?session_id=${Uri.encodeQueryComponent(sessionId)}');

  @override
  Future<List<DictionaryEntry>> dataDictionary(int studyId) async {
    final bytes = await _api.getBytes('${_base(studyId)}/data-dictionary.json');
    try {
      return DictionaryEntry.listFromJson(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      throw const ApiException('The server sent an unexpected response.');
    }
  }
}

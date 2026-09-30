import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/pilot_repository.dart';

class ApiPilotRepository implements PilotRepository {
  ApiPilotRepository(this._api);

  final ApiClient _api;

  String _study(int studyId) => '/studies/$studyId';

  String _session(int studyId, String sessionId) =>
      '${_study(studyId)}/sessions/${Uri.encodeComponent(sessionId)}';

  @override
  Future<List<SettingsVersion>> settingsHistory(int studyId) async =>
      SettingsVersion.listFromJson(
        await _api.getList('${_study(studyId)}/measurement-settings/history'),
      );

  @override
  Future<ThresholdReview> thresholdReview(
    int studyId, {
    Map<String, dynamic> changes = const {},
    bool includeSynthetic = false,
  }) async =>
      ThresholdReview.fromJson(
        await _api.postObject('${_study(studyId)}/pilot/threshold-review', {
          'changes': changes,
          'include_synthetic': includeSynthetic,
        }),
      );

  @override
  Future<List<Observation>> observations(int studyId, String sessionId) async =>
      Observation.listFromJson(
        await _api.getList('${_session(studyId, sessionId)}/observations'),
      );

  @override
  Future<Observation> addObservation(
    int studyId,
    String sessionId,
    ObservationRequest request,
  ) async =>
      Observation.fromJson(
        await _api.postObject(
          '${_session(studyId, sessionId)}/observations',
          request.toJson(),
        ),
      );

  @override
  Future<List<ActiveSession>> activeSessions(int studyId) async =>
      ActiveSession.listFromJson(
        await _api.getList('${_study(studyId)}/pilot/active'),
      );

  @override
  Future<LiveStatus> live(
    int studyId,
    String sessionId, {
    bool first = false,
  }) async =>
      LiveStatus.fromJson(
        await _api.getObject('${_session(studyId, sessionId)}/live?first=$first'),
      );

  @override
  Future<DebriefForm> debriefForm(int studyId) async => DebriefForm.fromJson(
        await _api.getObject('${_study(studyId)}/debrief-form'),
      );

  @override
  Future<DebriefForm> saveDebriefForm(
    int studyId, {
    List<DebriefQuestion>? questions,
    bool? enabled,
  }) async =>
      DebriefForm.fromJson(
        await _api.putObject('${_study(studyId)}/debrief-form', {
          if (questions != null)
            'questions': [for (final q in questions) q.toJson()],
          'enabled': ?enabled,
        }),
      );

  /// The media type for a tracker export; the server reads the content, not
  /// the type, so this only labels the part.
  static String contentTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.tsv')) return 'text/tab-separated-values';
    return 'text/plain';
  }

  @override
  Future<ReferenceRecording> importReference(
    int studyId,
    String sessionId, {
    required Uint8List bytes,
    required String filename,
    required ReferenceImportRequest request,
  }) async =>
      ReferenceRecording.fromJson(
        await _api.uploadFile(
          '${_session(studyId, sessionId)}/reference',
          bytes: bytes,
          filename: filename,
          contentType: contentTypeFor(filename),
          fields: request.toFields(),
        ),
      );

  @override
  Future<List<ReferenceRecording>> references(
    int studyId,
    String sessionId,
  ) async =>
      ReferenceRecording.listFromJson(
        await _api.getList('${_session(studyId, sessionId)}/reference'),
      );

  @override
  Future<ReferenceComparison> compare(
    int studyId,
    String sessionId,
    String recordingId, {
    int toleranceMs = 40,
  }) async =>
      ReferenceComparison.fromJson(
        await _api.getObject(
          '${_session(studyId, sessionId)}/reference/'
          '${Uri.encodeComponent(recordingId)}/compare?tolerance_ms=$toleranceMs',
        ),
      );

  @override
  Future<PilotReport> report(int studyId, {bool includeSynthetic = false}) async =>
      PilotReport.fromJson(
        await _api.getObject(
          '${_study(studyId)}/pilot/report?include_synthetic=$includeSynthetic',
        ),
      );

  @override
  Future<Uint8List> reportCsv(int studyId, {bool includeSynthetic = false}) =>
      _api.getBytes(
        '${_study(studyId)}/pilot/report.csv?include_synthetic=$includeSynthetic',
      );
}

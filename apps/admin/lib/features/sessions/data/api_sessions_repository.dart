import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/sessions_repository.dart';

class ApiSessionsRepository implements SessionsRepository {
  ApiSessionsRepository(this._api);

  final ApiClient _api;

  String _base(int studyId) => '/studies/$studyId/sessions';

  @override
  Future<List<SessionListItem>> list(int studyId) async => [
        for (final s in await _api.getList(_base(studyId)))
          SessionListItem.fromJson(s as Map<String, dynamic>),
      ];

  @override
  Future<SessionDetail> detail(int studyId, String sessionId) async =>
      SessionDetail.fromJson(
        await _api.getObject(
          '${_base(studyId)}/${Uri.encodeComponent(sessionId)}',
        ),
      );

  @override
  Future<SamplesPage> samples(
    int studyId,
    String sessionId, {
    int offset = 0,
    int limit = 100,
  }) async =>
      SamplesPage.fromJson(
        await _api.getObject(
          '${_base(studyId)}/${Uri.encodeComponent(sessionId)}/samples'
          '?offset=$offset&limit=$limit',
        ),
      );
}

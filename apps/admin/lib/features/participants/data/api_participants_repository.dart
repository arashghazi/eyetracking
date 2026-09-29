import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/participants_repository.dart';

class ApiParticipantsRepository implements ParticipantsRepository {
  ApiParticipantsRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ParticipantRecord>> list(int studyId) async => [
        for (final p in await _api.getList('/studies/$studyId/participants'))
          ParticipantRecord.fromJson(p as Map<String, dynamic>),
      ];

  @override
  Future<ParticipantRecord> get(int studyId, String code) async =>
      ParticipantRecord.fromJson(
        await _api.getObject(
          '/studies/$studyId/participants/${Uri.encodeComponent(code)}',
        ),
      );

  @override
  Future<String> identity(int studyId, String code) async {
    final json = await _api.getObject(
      '/studies/$studyId/participants/${Uri.encodeComponent(code)}/identity',
    );
    return json['email'] as String? ?? '';
  }

  @override
  Future<EraseResult> deleteData(int studyId, String code, String confirm) async {
    final answer = await _api.delete(
      '/studies/$studyId/participants/${Uri.encodeComponent(code)}/data',
      {'confirm': confirm},
    );
    return answer is Map<String, dynamic>
        ? EraseResult.fromJson(answer)
        : const EraseResult();
  }
}

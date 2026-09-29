import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/studies_repository.dart';
import '../domain/study.dart';

class ApiStudiesRepository implements StudiesRepository {
  ApiStudiesRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Study>> list() async => [
        for (final s in await _api.getList('/studies'))
          Study.fromJson(s as Map<String, dynamic>),
      ];

  @override
  Future<Study> create(String name) async =>
      Study.fromJson(await _api.postObject('/studies', {'name': name}));

  @override
  Future<Study> get(int studyId) async =>
      Study.fromJson(await _api.getObject('/studies/$studyId'));

  @override
  Future<Study> setRetentionPolicy(int studyId, String policy) async {
    final answer = await _api.put('/studies/$studyId', {'retention_policy': policy});
    // The answer is the study; when it is not, read it back.
    if (answer is Map<String, dynamic> && answer['id'] != null) {
      return Study.fromJson(answer);
    }
    return get(studyId);
  }
}

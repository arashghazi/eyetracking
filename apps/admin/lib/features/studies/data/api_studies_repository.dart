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
}

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/erase_repository.dart';

class ApiEraseRepository implements EraseRepository {
  ApiEraseRepository(this._api);

  final ApiClient _api;

  @override
  Future<EraseResult> eraseMyData(String confirm) async => EraseResult.fromJson(
        await _api.postObject('/me/erase', {'confirm': confirm}),
      );
}

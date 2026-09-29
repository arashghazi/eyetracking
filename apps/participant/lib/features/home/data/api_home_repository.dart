import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/home_repository.dart';
import '../domain/participant_overview.dart';

class ApiHomeRepository implements HomeRepository {
  ApiHomeRepository(this._api);

  final ApiClient _api;

  @override
  Future<ParticipantOverview> loadOverview() async =>
      ParticipantOverview.fromJson(await _api.getObject('/me/participant'));
}

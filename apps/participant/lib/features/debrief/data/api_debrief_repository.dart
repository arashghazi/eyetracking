import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/debrief_models.dart';
import '../domain/debrief_repository.dart';

class ApiDebriefRepository implements DebriefRepository {
  ApiDebriefRepository(this._api);

  final ApiClient _api;

  String _path(String sessionId) =>
      '/me/sessions/${Uri.encodeComponent(sessionId)}/debrief';

  @override
  Future<SessionDebrief> load(String sessionId) async =>
      SessionDebrief.fromJson(await _api.getObject(_path(sessionId)));

  @override
  Future<DebriefAnswer> submit(String sessionId, DebriefAnswer answer) async =>
      DebriefAnswer.fromJson(
        await _api.postObject(_path(sessionId), answer.toJson()),
      );
}

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/live_models.dart';
import '../domain/live_repository.dart';

class ApiLiveRepository implements LiveRepository {
  ApiLiveRepository(this._api);

  final ApiClient _api;

  @override
  Future<LiveAvatarStatus> status(int studyId) async =>
      LiveAvatarStatus.fromJson(
        await _api.getObject('/studies/$studyId/live/status'),
      );

  @override
  Future<StaffConversation?> conversation(int studyId, String sessionId) async {
    // A session without a conversation answers 404, which is not an error.
    final json = await _api.getObjectOrNull(
      '/studies/$studyId/sessions/${Uri.encodeComponent(sessionId)}/conversation',
    );
    return json == null ? null : StaffConversation.fromJson(json);
  }
}

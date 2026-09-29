import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/invitation.dart';
import '../domain/invitations_repository.dart';

class ApiInvitationsRepository implements InvitationsRepository {
  ApiInvitationsRepository(this._api);

  final ApiClient _api;

  @override
  Future<Invitation> create(
    int studyId, {
    String? inviteeEmail,
    required int expiresDays,
  }) async {
    final json = await _api.postObject('/studies/$studyId/invitations', {
      'invitee_email': ?inviteeEmail,
      'expires_days': expiresDays,
    });
    return Invitation.fromJson(json, inviteeEmail: inviteeEmail);
  }
}

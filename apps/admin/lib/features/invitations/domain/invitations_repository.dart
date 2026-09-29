import 'invitation.dart';

abstract class InvitationsRepository {
  Future<Invitation> create(
    int studyId, {
    String? inviteeEmail,
    required int expiresDays,
  });
}

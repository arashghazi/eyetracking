import 'live_models.dart';

/// Staff reads of the live avatar (researchers and analysts). Live
/// conversations belong to sessions; the participant side is in the
/// participant app.
abstract class LiveRepository {
  /// `GET /studies/{id}/live/status`: providers, estimates, the shared
  /// budget and the open conversations.
  Future<LiveAvatarStatus> status(int studyId);

  /// `GET /studies/{id}/sessions/{sid}/conversation`. Null when the session
  /// has no conversation (404). Every read that succeeds is written to the
  /// access log as `live_transcript`.
  Future<StaffConversation?> conversation(int studyId, String sessionId);
}

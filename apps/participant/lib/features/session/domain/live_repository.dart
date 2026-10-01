import 'package:eyetracking_core/eyetracking_core.dart';

/// What the live conversation needs from the research server: the `live`
/// endpoints of the step 7 contract (docs/api/step7-live-avatar.md).
///
/// Every method throws an [ApiException] whose message is safe to show. A
/// 409 means the conversation moved on (a turn was already sent, it has
/// ended, speech is not available); a 422 means the input was refused (an
/// empty message, speech that could not be understood, no budget).
abstract class LiveRepository {
  /// `GET /me/sessions/{sid}/live`: where the conversation stands, or
  /// nothing yet, plus what may be chosen before it starts.
  Future<LiveSnapshot> snapshot(String sessionId);

  /// `POST /me/sessions/{sid}/live/start`. Calling it again while the
  /// conversation is open returns it with `resumed: true`. The avatar's
  /// video address is already resolved against the service address.
  Future<LiveStart> start(
    String sessionId, {
    required LiveInputMode mode,
    required bool allowTranscript,
    int? tMs,
  });

  /// `POST /me/sessions/{sid}/live/turn`; [expectTurn] must equal the turns
  /// used so far, which makes a double send fail with 409.
  Future<LiveTurnResult> sendTurn(
    String sessionId, {
    required int expectTurn,
    required String text,
    int? tMs,
  });

  /// `POST /me/sessions/{sid}/live/turn-audio` (multipart). The service
  /// turns the speech into text in memory and never keeps the recording.
  Future<LiveTurnResult> sendAudio(
    String sessionId, {
    required int expectTurn,
    required AudioClip clip,
    int? tMs,
  });

  /// `POST /me/sessions/{sid}/live/end`: the participant ends it.
  Future<LiveEndResult> end(String sessionId, {int? tMs});
}

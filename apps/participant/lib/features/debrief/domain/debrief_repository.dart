import 'debrief_models.dart';

/// What the debrief card needs from the research server.
abstract class DebriefRepository {
  /// The form for a session and any earlier answer.
  Future<SessionDebrief> load(String sessionId);

  /// Sends the answers or a skip. Throws an `ApiException`: 409 when the
  /// session is not ended, the form is off, its version changed or the
  /// session is already answered; 422 for a missing required or invalid
  /// value. The message is the server's, ready to show.
  Future<DebriefAnswer> submit(String sessionId, DebriefAnswer answer);
}

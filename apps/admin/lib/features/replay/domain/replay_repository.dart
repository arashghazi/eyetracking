import 'package:eyetracking_core/eyetracking_core.dart';

/// Read access to the replay bundle of one session. Every replay is written
/// to the study's access log by the server.
abstract class ReplayRepository {
  Future<ReplayBundle> load(int studyId, String sessionId);
}

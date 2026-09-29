import 'package:eyetracking_core/eyetracking_core.dart';

/// Read access to a study's measurement sessions (researchers and analysts).
abstract class SessionsRepository {
  Future<List<SessionListItem>> list(int studyId);

  Future<SessionDetail> detail(int studyId, String sessionId);

  /// One page of stored, classified samples.
  Future<SamplesPage> samples(
    int studyId,
    String sessionId, {
    int offset = 0,
    int limit = 100,
  });
}

import 'package:eyetracking_core/eyetracking_core.dart';

/// The study's access log (researchers and administrators who are members).
abstract class AccessLogRepository {
  Future<List<AccessLogEntry>> list(int studyId, {int limit = 200});
}

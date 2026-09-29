import 'package:eyetracking_core/eyetracking_core.dart';

/// Assignment endpoints of one participant, for researchers.
abstract class AssignmentsRepository {
  Future<List<Assignment>> list(int studyId, String code);

  /// Assigns a published protocol; [orderIndex] places it in the participant's
  /// sequence (the server appends when omitted).
  Future<Assignment> create(
    int studyId,
    String code, {
    required String protocolId,
    int? orderIndex,
  });

  /// Attaches approved, matching content to an assignment that waits for it.
  Future<Assignment> attachContent(
    int studyId,
    String code,
    String assignmentId,
    String contentId,
  );

  Future<Assignment> cancel(int studyId, String code, String assignmentId);
}

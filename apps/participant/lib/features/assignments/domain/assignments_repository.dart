import 'package:eyetracking_core/eyetracking_core.dart';

/// What the participant app needs from the assignment endpoints of the
/// step 3 contract.
abstract class AssignmentsRepository {
  /// `GET /me/assignments`, ordered.
  Future<List<Assignment>> list();

  /// `POST /me/assignments/{id}/topic`; the assignment then waits for content.
  Future<Assignment> submitTopic(
    String assignmentId, {
    required String topic,
    String? freeText,
  });

  /// `GET /me/assignments/{id}/content`: the personalized interest content
  /// with signed media URLs (404 until the assignment is ready).
  Future<PersonalizedContent> content(String assignmentId);
}

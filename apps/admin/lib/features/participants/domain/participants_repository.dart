import 'package:eyetracking_core/eyetracking_core.dart';

abstract class ParticipantsRepository {
  Future<List<ParticipantRecord>> list(int studyId);

  Future<ParticipantRecord> get(int studyId, String code);

  /// The login email behind a research code. Needs the identity-link grant;
  /// throws an [ApiException] with status 403 without it.
  Future<String> identity(int studyId, String code);

  /// Researchers: deletes the participant's research rows (sessions and
  /// everything under them, consents, demographics, profile, assignments).
  /// [confirm] must be the research code, which the server checks again.
  /// The account and the code stay, so the person can still sign in.
  Future<EraseResult> deleteData(int studyId, String code, String confirm);
}

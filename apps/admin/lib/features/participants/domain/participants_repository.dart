import 'package:eyetracking_core/eyetracking_core.dart';

abstract class ParticipantsRepository {
  Future<List<ParticipantRecord>> list(int studyId);

  Future<ParticipantRecord> get(int studyId, String code);

  /// The login email behind a research code. Needs the identity-link grant;
  /// throws an [ApiException] with status 403 without it.
  Future<String> identity(int studyId, String code);
}

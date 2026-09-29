import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/members_repository.dart';

class ApiMembersRepository implements MembersRepository {
  ApiMembersRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> addMember({
    required int studyId,
    required int userId,
    required StudyRole studyRole,
    required bool canLinkIdentity,
  }) async {
    await _api.post('/studies/$studyId/members', {
      'user_id': userId,
      'study_role': studyRole.wire,
      'can_link_identity': canLinkIdentity,
    });
  }

  @override
  Future<StaffAccount> createStaff({
    required String email,
    required String password,
    required StaffRole role,
  }) async =>
      StaffAccount.fromJson(await _api.postObject('/users', {
        'email': email,
        'password': password,
        'role': role.wire,
      }));
}

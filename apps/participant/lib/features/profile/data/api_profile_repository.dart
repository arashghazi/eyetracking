import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/profile_repository.dart';

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<Profile> load() async =>
      Profile.fromJson(await _api.getObject('/me/profile'));

  @override
  Future<Profile> save(Profile profile) async =>
      Profile.fromJson(await _api.putObject('/me/profile', profile.toJson()));
}

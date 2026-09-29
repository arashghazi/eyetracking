import 'package:eyetracking_core/eyetracking_core.dart';

abstract class ProfileRepository {
  Future<Profile> load();

  Future<Profile> save(Profile profile);
}

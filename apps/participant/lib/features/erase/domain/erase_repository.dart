import 'package:eyetracking_core/eyetracking_core.dart';

abstract class EraseRepository {
  /// Withdraws and deletes the participant's data and closes the account.
  /// [confirm] must be the phrase the person typed.
  Future<EraseResult> eraseMyData(String confirm);
}

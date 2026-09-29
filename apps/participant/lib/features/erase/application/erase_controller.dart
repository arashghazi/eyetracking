import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/erase_repository.dart';

/// "Withdraw and delete my data": the participant types a phrase, the
/// service deletes their data and closes the account, and the app signs out
/// with a farewell.
class EraseController extends SafeChangeNotifier {
  EraseController(this._repository, {required this.onErased});

  /// The phrase that must be typed, exactly.
  static const phrase = 'DELETE MY DATA';

  final EraseRepository _repository;

  /// Called after the service confirmed the deletion, with what happened.
  final void Function(EraseResult result) onErased;

  bool _busy = false;
  String? _error;

  bool get busy => _busy;
  String? get error => _error;

  /// True when [typed] is the phrase (spaces around it are ignored; the
  /// letters must match exactly).
  static bool matches(String typed) => typed.trim() == phrase;

  Future<bool> erase(String typed) async {
    if (_busy) return false;
    if (!matches(typed)) {
      _error = 'Type $phrase exactly to confirm.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.eraseMyData(phrase);
      onErased(result);
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  /// The message on the sign-in screen after the account was closed.
  static String farewell(EraseResult result) => result.policy ==
          RetentionPolicy.keepCoded
      ? 'Your account is closed and your link to the study is removed. As the '
          'information sheet explains, coded research data without your name '
          'or email stays with the study. Thank you for taking part.'
      : 'Your data has been deleted and your account is closed. Thank you for '
          'taking part.';
}

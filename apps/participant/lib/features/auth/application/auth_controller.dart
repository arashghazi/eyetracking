import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';

/// Owns the signed-in session and the state of the sign-in forms.
class AuthController extends SafeChangeNotifier {
  AuthController(this._repository);

  static const _role = 'participant';

  final AuthRepository _repository;

  AuthSession? _session;
  bool _busy = false;
  String? _error;
  String? _notice;

  AuthSession? get session => _session;
  bool get isSignedIn => _session != null;
  bool get busy => _busy;
  String? get error => _error;

  /// A message for the sign-in screen that is not an error, for example the
  /// farewell after the participant erased their data.
  String? get notice => _notice;

  Future<bool> signIn(String email, String password) => _run(
        () => _repository.signIn(email: email.trim(), password: password),
      );

  Future<bool> acceptInvitation({
    required String token,
    required String email,
    required String password,
  }) =>
      _run(
        () => _repository.acceptInvitation(
          token: token.trim(),
          email: email.trim(),
          password: password,
        ),
      );

  void signOut() {
    _repository.signOut();
    _session = null;
    notifyListeners();
  }

  /// Signs out and leaves [message] on the sign-in screen (the account was
  /// closed, so there is nothing to sign in to any more).
  void signOutWithNotice(String message) {
    _repository.signOut();
    _session = null;
    _error = null;
    _notice = message;
    notifyListeners();
  }

  /// The server rejected our token: return to sign-in with an explanation.
  void expire() {
    if (_session == null) return;
    _repository.signOut();
    _session = null;
    _error = 'Your session has ended. Please sign in again.';
    notifyListeners();
  }

  void dismissError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  Future<bool> _run(Future<AuthSession> Function() action) async {
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final session = await action();
      if (session.role != _role) {
        _repository.signOut();
        _error = 'This account is not a participant account. '
            'Staff accounts sign in to the Research Admin.';
        return false;
      }
      _session = session;
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

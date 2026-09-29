import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';

/// Owns the signed-in staff session and the state of the sign-in form.
class AuthController extends SafeChangeNotifier {
  AuthController(this._repository);

  static const staffRoles = {'researcher', 'analyst', 'admin'};

  final AuthRepository _repository;

  AuthSession? _session;
  bool _busy = false;
  String? _error;

  AuthSession? get session => _session;
  bool get isSignedIn => _session != null;
  bool get isAdmin => _session?.isAdmin ?? false;
  bool get busy => _busy;
  String? get error => _error;

  Future<bool> signIn(String email, String password) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final session =
          await _repository.signIn(email: email.trim(), password: password);
      if (!staffRoles.contains(session.role)) {
        _repository.signOut();
        _error = 'This account is not a staff account. '
            'Participants sign in to the Participant App.';
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

  void signOut() {
    _repository.signOut();
    _session = null;
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
}

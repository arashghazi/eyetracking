import 'auth_session.dart';

abstract class AuthRepository {
  Future<AuthSession> signIn({required String email, required String password});

  Future<AuthSession> acceptInvitation({
    required String token,
    required String email,
    required String password,
  });

  /// Forgets the credentials held for the current session.
  void signOut();
}

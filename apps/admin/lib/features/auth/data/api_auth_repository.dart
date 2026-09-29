import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final json = await _api.postObject(
      '/auth/login',
      {'email': email, 'password': password},
    );
    final token = json['access_token'];
    if (token is! String) {
      throw const ApiException('The server sent an unexpected response.');
    }
    _api.tokenStore.save(token);
    return AuthSession(role: json['role'] as String? ?? '');
  }

  @override
  void signOut() => _api.tokenStore.clear();
}

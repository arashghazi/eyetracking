/// Who is signed in. The bearer token itself stays inside the data layer.
class AuthSession {
  const AuthSession({required this.role});

  /// Account role: `researcher`, `analyst` or `admin`.
  final String role;

  bool get isAdmin => role == 'admin';
}

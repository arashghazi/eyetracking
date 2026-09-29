/// Who is signed in. The bearer token itself stays inside the data layer.
class AuthSession {
  const AuthSession({required this.role, this.participantCode});

  final String role;
  final String? participantCode;
}

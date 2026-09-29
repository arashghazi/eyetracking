class Invitation {
  const Invitation({
    required this.token,
    required this.code,
    this.expiresAt,
    this.inviteeEmail,
  });

  final String token;
  final String code;
  final String? expiresAt;

  /// Email the invitation was restricted to, when one was given.
  final String? inviteeEmail;

  factory Invitation.fromJson(Map<String, dynamic> json, {String? inviteeEmail}) =>
      Invitation(
        token: json['token'] as String? ?? '',
        code: json['code'] as String? ?? '',
        expiresAt: json['expires_at'] as String?,
        inviteeEmail: inviteeEmail,
      );
}

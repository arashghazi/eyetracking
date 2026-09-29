class StaffAccount {
  const StaffAccount({required this.id, required this.email, required this.role});

  final int id;
  final String email;
  final String role;

  factory StaffAccount.fromJson(Map<String, dynamic> json) => StaffAccount(
        id: (json['id'] as num).toInt(),
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? '',
      );
}

/// Study roles a member can hold.
enum StudyRole {
  researcher('researcher', 'Researcher'),
  analyst('analyst', 'Analyst');

  const StudyRole(this.wire, this.label);
  final String wire;
  final String label;
}

/// Account roles for staff accounts.
enum StaffRole {
  researcher('researcher', 'Researcher'),
  analyst('analyst', 'Analyst'),
  admin('admin', 'Admin');

  const StaffRole(this.wire, this.label);
  final String wire;
  final String label;
}

abstract class MembersRepository {
  Future<void> addMember({
    required int studyId,
    required int userId,
    required StudyRole studyRole,
    required bool canLinkIdentity,
  });

  Future<StaffAccount> createStaff({
    required String email,
    required String password,
    required StaffRole role,
  });
}

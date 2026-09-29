import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:research_admin/app_dependencies.dart';
import 'package:research_admin/features/auth/application/auth_controller.dart';
import 'package:research_admin/features/auth/domain/auth_repository.dart';
import 'package:research_admin/features/auth/domain/auth_session.dart';
import 'package:research_admin/features/demographics_form/domain/demographics_form_repository.dart';
import 'package:research_admin/features/information_sheet/domain/information_sheet_repository.dart';
import 'package:research_admin/features/invitations/domain/invitation.dart';
import 'package:research_admin/features/invitations/domain/invitations_repository.dart';
import 'package:research_admin/features/members/domain/members_repository.dart';
import 'package:research_admin/features/participants/domain/participants_repository.dart';
import 'package:research_admin/features/studies/domain/studies_repository.dart';
import 'package:research_admin/features/studies/domain/study.dart';

class FakeAuthRepository implements AuthRepository {
  ApiException? failure;
  String role = 'admin';
  bool signedOut = false;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    if (failure != null) throw failure!;
    return AuthSession(role: role);
  }

  @override
  void signOut() => signedOut = true;
}

class FakeStudiesRepository implements StudiesRepository {
  final List<Study> studies = [
    const Study(id: 1, name: 'Face attention pilot'),
    const Study(id: 2, name: 'Second study'),
  ];
  final List<String> created = [];

  @override
  Future<List<Study>> list() async => List.of(studies);

  @override
  Future<Study> create(String name) async {
    created.add(name);
    final study = Study(id: studies.length + 1, name: name);
    studies.add(study);
    return study;
  }
}

const readyRecord = ParticipantRecord(
  code: 'P-001',
  readiness: Readiness(ready: true),
  consent: Consent(
    sheetVersion: 3,
    participate: true,
    audioRecording: true,
    givenAt: '2026-09-02T09:30:00Z',
  ),
  profile: Profile(
    displayName: 'Sam',
    responseMode: ResponseMode.keyboard,
    interests: ['trains'],
  ),
  demographics: DemographicsAnswers(formVersion: 2, answers: {'age': 34}),
);

const waitingRecord = ParticipantRecord(
  code: 'P-002',
  readiness: Readiness(ready: false, reasons: [
    ReadinessReason.consentMissingOrOutdated,
    ReadinessReason.demographicsIncomplete,
  ]),
);

const withdrawnRecord = ParticipantRecord(
  code: 'P-003',
  readiness: Readiness(ready: false, reasons: [
    ReadinessReason.consentMissingOrOutdated,
  ]),
  consent: Consent(
    sheetVersion: 2,
    participate: true,
    withdrawnAt: '2026-09-05T08:00:00Z',
  ),
);

class FakeParticipantsRepository implements ParticipantsRepository {
  List<ParticipantRecord> records = [readyRecord, waitingRecord, withdrawnRecord];
  ApiException? identityFailure;
  final List<String> identityRequests = [];

  @override
  Future<List<ParticipantRecord>> list(int studyId) async => records;

  @override
  Future<ParticipantRecord> get(int studyId, String code) async =>
      records.firstWhere((r) => r.code == code);

  @override
  Future<String> identity(int studyId, String code) async {
    identityRequests.add(code);
    if (identityFailure != null) throw identityFailure!;
    return 'sam@example.org';
  }
}

class FakeInvitationsRepository implements InvitationsRepository {
  final List<Map<String, Object?>> requests = [];

  @override
  Future<Invitation> create(
    int studyId, {
    String? inviteeEmail,
    required int expiresDays,
  }) async {
    requests.add({'email': inviteeEmail, 'days': expiresDays});
    return Invitation(
      token: 'tok-abc-${requests.length}',
      code: 'P-00${requests.length + 3}',
      expiresAt: '2026-10-13T12:00:00Z',
      inviteeEmail: inviteeEmail,
    );
  }
}

class FakeInformationSheetRepository implements InformationSheetRepository {
  FakeInformationSheetRepository({this.sheet});

  InformationSheet? sheet;
  final List<SheetContent> published = [];

  @override
  Future<InformationSheet?> current(int studyId) async => sheet;

  @override
  Future<InformationSheet> publish(int studyId, SheetContent content) async {
    published.add(content);
    return sheet = InformationSheet(
      version: (sheet?.version ?? 0) + 1,
      content: content,
      publishedAt: '2026-09-10T10:00:00Z',
    );
  }
}

class FakeDemographicsFormRepository implements DemographicsFormRepository {
  FakeDemographicsFormRepository({this.form});

  DemographicsForm? form;
  final List<List<Map<String, dynamic>>> published = [];

  @override
  Future<DemographicsForm?> current(int studyId) async => form;

  @override
  Future<DemographicsForm> publish(
    int studyId,
    List<DemographicsField> fields,
  ) async {
    published.add([for (final f in fields) f.toJson()]);
    return form = DemographicsForm(
      version: (form?.version ?? 0) + 1,
      fields: fields,
    );
  }
}

class FakeMembersRepository implements MembersRepository {
  final List<Map<String, Object?>> added = [];
  final List<Map<String, Object?>> staff = [];
  ApiException? failure;

  @override
  Future<void> addMember({
    required int studyId,
    required int userId,
    required StudyRole studyRole,
    required bool canLinkIdentity,
  }) async {
    if (failure != null) throw failure!;
    added.add({
      'study': studyId,
      'user': userId,
      'role': studyRole.wire,
      'link': canLinkIdentity,
    });
  }

  @override
  Future<StaffAccount> createStaff({
    required String email,
    required String password,
    required StaffRole role,
  }) async {
    staff.add({'email': email, 'role': role.wire});
    return StaffAccount(id: 40 + staff.length, email: email, role: role.wire);
  }
}

class TestBed {
  TestBed({
    FakeParticipantsRepository? participants,
    FakeInformationSheetRepository? informationSheet,
    FakeDemographicsFormRepository? demographicsForm,
  })  : authRepository = FakeAuthRepository(),
        studies = FakeStudiesRepository(),
        participants = participants ?? FakeParticipantsRepository(),
        invitations = FakeInvitationsRepository(),
        informationSheet = informationSheet ?? FakeInformationSheetRepository(),
        demographicsForm = demographicsForm ?? FakeDemographicsFormRepository(),
        members = FakeMembersRepository() {
    auth = AuthController(authRepository);
  }

  final FakeAuthRepository authRepository;
  late final AuthController auth;
  final FakeStudiesRepository studies;
  final FakeParticipantsRepository participants;
  final FakeInvitationsRepository invitations;
  final FakeInformationSheetRepository informationSheet;
  final FakeDemographicsFormRepository demographicsForm;
  final FakeMembersRepository members;

  AppDependencies get dependencies => AppDependencies(
        auth: auth,
        studies: studies,
        participants: participants,
        invitations: invitations,
        informationSheet: informationSheet,
        demographicsForm: demographicsForm,
        members: members,
      );
}

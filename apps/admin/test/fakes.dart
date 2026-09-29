import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:research_admin/app_dependencies.dart';
import 'package:research_admin/features/auth/application/auth_controller.dart';
import 'package:research_admin/features/auth/domain/auth_repository.dart';
import 'package:research_admin/features/auth/domain/auth_session.dart';
import 'package:research_admin/features/demographics_form/domain/demographics_form_repository.dart';
import 'package:research_admin/features/information_sheet/domain/information_sheet_repository.dart';
import 'package:research_admin/features/invitations/domain/invitation.dart';
import 'package:research_admin/features/invitations/domain/invitations_repository.dart';
import 'package:research_admin/features/measurement_settings/domain/measurement_settings_repository.dart';
import 'package:research_admin/features/members/domain/members_repository.dart';
import 'package:research_admin/features/participants/domain/participants_repository.dart';
import 'package:research_admin/features/sessions/domain/sessions_repository.dart';
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

const sessionItems = [
  SessionListItem(
    id: '21',
    participantCode: 'P-001',
    status: SessionStatus.ended,
    createdAt: '2026-09-29T08:00:00',
    synthetic: true,
    devicePlatform: 'web',
    calibrationResidualPx: 88.4,
    validationPassed: false,
    coverage: Coverage(
      totalMs: 30000,
      classifiableMs: 21000,
      uncertainMs: 6000,
      missingMs: 3000,
    ),
    eyeRegionAttention: EyeRegionAttention(
      evaluable: false,
      reason: 'Estimator is synthetic.',
    ),
  ),
  SessionListItem(
    id: '22',
    participantCode: 'P-002',
    status: SessionStatus.calibrated,
    createdAt: '2026-09-30T09:30:00',
    calibrationResidualPx: 52,
  ),
  SessionListItem(
    id: '23',
    participantCode: 'P-003',
    status: SessionStatus.ended,
    createdAt: '2026-10-01T10:15:00',
    calibrationResidualPx: 41.2,
    validationPassed: true,
    coverage: Coverage(
      totalMs: 20000,
      classifiableMs: 18000,
      uncertainMs: 1500,
      missingMs: 500,
    ),
    eyeRegionAttention: EyeRegionAttention(evaluable: true, share: 0.43),
  ),
];

const sessionDetailJson = <String, dynamic>{
  'id': 21,
  'status': 'ended',
  'created_at': '2026-09-29T08:00:00',
  'ended_at': '2026-09-29T08:05:00',
  'end_reason': 'completed',
  'synthetic': true,
  'calibration_valid': true,
  'participant_code': 'P-001',
  'device': {'platform': 'web', 'user_agent': 'Mozilla/5.0 Test'},
  'screen': {'w': 1440, 'h': 900, 'dpr': 1.25},
  'camera': {'label': 'Integrated Camera', 'w': 640, 'h': 480},
  'gaze_model': {
    'model_id': 'stub-1',
    'model_version': '0.1',
    'synthetic': true,
  },
  'calibration': {
    'residual_px_median': 88.4,
    'residual_px_p90': 141.0,
    'points': 9,
  },
  'validation': {
    'passed': false,
    'correct_ratio': 0.5,
    'uncertain_ratio': 0.25,
    'size_ratio': 1.6,
    'reasons': ['Correct share is below 80 %.'],
  },
  // The real server sends the per-dot results next to `validation`.
  'validation_targets': [
    {
      'region': 'eye',
      'x': 700,
      'y': 300,
      'n': 14,
      'majority': 'face_other',
      'correct': false,
      'uncertain_share': 0.1,
    },
    {
      'region': 'mouth',
      'x': 720,
      'y': 520,
      'n': 13,
      'majority': 'mouth',
      'correct': true,
      'uncertain_share': 0.0,
    },
  ],
  'coverage': {
    'total_ms': 30000,
    'classifiable_ms': 21000,
    'uncertain_ms': 6000,
    'missing_ms': 3000,
  },
  'region_shares': {
    'eye': 0.1,
    'mouth': 0.2,
    'face_other': 0.4,
    'outside': 0.3,
  },
  'face_region_attention': {'share': 0.7},
  'eye_region_attention': {
    'evaluable': false,
    'share': null,
    'reason': 'Regional validation did not pass.',
  },
  'segments': [
    {'label': 'baseline', 'started_ms': 4000, 'ended_ms': 34000},
  ],
  'events_count': 3,
  'events': [
    {
      't_ms': 4000,
      'type': 'segment_start',
      'payload': {'segment': 'baseline'},
    },
    {'t_ms': 12000, 'type': 'face_lost'},
    {
      't_ms': 34000,
      'type': 'end',
      'payload': {'reason': 'completed'},
    },
  ],
  'notes': [],
};

class FakeSessionsRepository implements SessionsRepository {
  FakeSessionsRepository({
    this.items = sessionItems,
    this.sampleTotal = 250,
  });

  List<SessionListItem> items;
  int sampleTotal;
  ApiException? failure;
  final List<({int offset, int limit})> sampleRequests = [];

  @override
  Future<List<SessionListItem>> list(int studyId) async {
    if (failure != null) throw failure!;
    return items;
  }

  @override
  Future<SessionDetail> detail(int studyId, String sessionId) async =>
      SessionDetail.fromJson(sessionDetailJson);

  @override
  Future<SamplesPage> samples(
    int studyId,
    String sessionId, {
    int offset = 0,
    int limit = 100,
  }) async {
    sampleRequests.add((offset: offset, limit: limit));
    final count = (sampleTotal - offset).clamp(0, limit);
    return SamplesPage(
      total: sampleTotal,
      items: [
        for (var i = 0; i < count; i++)
          SampleRow(
            tMs: (offset + i) * 100,
            x: 700.0 + i,
            y: 400.0,
            conf: 0.8,
            valid: true,
            region: 'face_other',
            segment: 'baseline',
          ),
      ],
    );
  }
}

class FakeMeasurementSettingsRepository
    implements MeasurementSettingsRepository {
  MeasurementSettings settings = MeasurementSettings.defaults;
  final List<MeasurementSettings> saved = [];
  ApiException? saveFailure;

  @override
  Future<MeasurementSettings> load(int studyId) async => settings;

  @override
  Future<MeasurementSettings> save(
    int studyId,
    MeasurementSettings next,
  ) async {
    if (saveFailure != null) throw saveFailure!;
    saved.add(next);
    return settings = next;
  }
}

class TestBed {
  TestBed({
    FakeParticipantsRepository? participants,
    FakeInformationSheetRepository? informationSheet,
    FakeDemographicsFormRepository? demographicsForm,
    FakeSessionsRepository? sessions,
    FakeMeasurementSettingsRepository? measurementSettings,
  })  : authRepository = FakeAuthRepository(),
        studies = FakeStudiesRepository(),
        participants = participants ?? FakeParticipantsRepository(),
        invitations = FakeInvitationsRepository(),
        informationSheet = informationSheet ?? FakeInformationSheetRepository(),
        demographicsForm = demographicsForm ?? FakeDemographicsFormRepository(),
        members = FakeMembersRepository(),
        sessions = sessions ?? FakeSessionsRepository(),
        measurementSettings =
            measurementSettings ?? FakeMeasurementSettingsRepository() {
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
  final FakeSessionsRepository sessions;
  final FakeMeasurementSettingsRepository measurementSettings;

  AppDependencies get dependencies => AppDependencies(
        auth: auth,
        studies: studies,
        participants: participants,
        invitations: invitations,
        informationSheet: informationSheet,
        demographicsForm: demographicsForm,
        members: members,
        sessions: sessions,
        measurementSettings: measurementSettings,
      );
}

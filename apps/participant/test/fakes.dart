import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:participant_app/app_dependencies.dart';
import 'package:participant_app/features/auth/application/auth_controller.dart';
import 'package:participant_app/features/auth/domain/auth_repository.dart';
import 'package:participant_app/features/auth/domain/auth_session.dart';
import 'package:participant_app/features/consent/domain/consent_repository.dart';
import 'package:participant_app/features/data_export/domain/data_export_repository.dart';
import 'package:participant_app/features/demographics/domain/demographics_repository.dart';
import 'package:participant_app/features/home/domain/home_repository.dart';
import 'package:participant_app/features/home/domain/participant_overview.dart';
import 'package:participant_app/features/profile/domain/profile_repository.dart';

class FakeAuthRepository implements AuthRepository {
  ApiException? failure;
  String role = 'participant';
  final List<String> signedInWith = [];
  final List<String> acceptedTokens = [];
  bool signedOut = false;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    if (failure != null) throw failure!;
    signedInWith.add(email);
    return AuthSession(role: role, participantCode: 'P-0001');
  }

  @override
  Future<AuthSession> acceptInvitation({
    required String token,
    required String email,
    required String password,
  }) async {
    if (failure != null) throw failure!;
    acceptedTokens.add(token);
    return const AuthSession(role: 'participant', participantCode: 'P-0002');
  }

  @override
  void signOut() => signedOut = true;
}

class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository({List<String> reasons = const []})
      : overview = ParticipantOverview(
          code: 'P-0001',
          studyId: 1,
          readiness: Readiness(ready: reasons.isEmpty, reasons: reasons),
        );

  ParticipantOverview overview;

  @override
  Future<ParticipantOverview> loadOverview() async => overview;
}

const sampleSheet = InformationSheet(
  version: 3,
  publishedAt: '2026-09-01T10:00:00Z',
  content: SheetContent(
    aims: 'We study how people look at faces.',
    discomfortSources: 'Looking at faces can feel uncomfortable.',
    benefits: 'You may learn about your own attention.',
    dataHandling: 'Data is stored under your research code.',
    stopRules: 'You can stop and restart whenever you like.',
  ),
);

class FakeConsentRepository implements ConsentRepository {
  FakeConsentRepository({this.sheet = sampleSheet, this.consent});

  InformationSheet? sheet;
  Consent? consent;
  final List<Map<String, Object>> given = [];
  int withdrawCalls = 0;

  @override
  Future<InformationSheet?> fetchSheet() async => sheet;

  @override
  Future<Consent?> fetchConsent() async => consent;

  @override
  Future<Consent> give({
    required int sheetVersion,
    required bool participate,
    required bool audioRecording,
    required bool videoRecording,
  }) async {
    given.add({
      'sheet_version': sheetVersion,
      'participate': participate,
      'audio_recording': audioRecording,
      'video_recording': videoRecording,
    });
    return consent = Consent(
      sheetVersion: sheetVersion,
      participate: participate,
      audioRecording: audioRecording,
      videoRecording: videoRecording,
      givenAt: '2026-09-02T09:30:00Z',
    );
  }

  @override
  Future<Consent> withdraw() async {
    withdrawCalls++;
    final old = consent!;
    return consent = Consent(
      sheetVersion: old.sheetVersion,
      participate: old.participate,
      givenAt: old.givenAt,
      withdrawnAt: '2026-09-03T09:30:00Z',
    );
  }
}

class FakeProfileRepository implements ProfileRepository {
  Profile profile = const Profile(displayName: 'Sam');
  final List<Profile> saved = [];

  @override
  Future<Profile> load() async => profile;

  @override
  Future<Profile> save(Profile p) async {
    saved.add(p);
    return profile = p;
  }
}

class FakeDemographicsRepository implements DemographicsRepository {
  FakeDemographicsRepository({this.form, this.answers});

  DemographicsForm? form;
  DemographicsAnswers? answers;
  final List<Map<String, Object?>> saved = [];

  @override
  Future<DemographicsForm?> fetchForm() async => form;

  @override
  Future<DemographicsAnswers?> fetchAnswers() async => answers;

  @override
  Future<DemographicsAnswers> save(Map<String, Object?> a) async {
    saved.add(a);
    return answers = DemographicsAnswers(formVersion: form!.version, answers: a);
  }
}

class FakeDataExportRepository implements DataExportRepository {
  @override
  Future<Object?> fetchMyData() async => {
        'participant': {'code': 'P-0001'},
        'consents': <Object?>[],
      };
}

const sampleForm = DemographicsForm(version: 2, fields: [
  DemographicsField(
    key: 'age',
    label: 'Age in years',
    type: DemographicsFieldType.number,
    required: true,
  ),
  DemographicsField(
    key: 'gender',
    label: 'Gender',
    type: DemographicsFieldType.choice,
    options: ['Woman', 'Man', 'Another description'],
  ),
  DemographicsField(
    key: 'notes',
    label: 'Anything else we should know',
    type: DemographicsFieldType.text,
  ),
  DemographicsField(
    key: 'glasses',
    label: 'I wear glasses',
    type: DemographicsFieldType.boolean,
  ),
]);

class TestBed {
  TestBed({
    FakeHomeRepository? home,
    FakeConsentRepository? consent,
    FakeProfileRepository? profile,
    FakeDemographicsRepository? demographics,
  })  : authRepository = FakeAuthRepository(),
        home = home ?? FakeHomeRepository(),
        consent = consent ?? FakeConsentRepository(),
        profile = profile ?? FakeProfileRepository(),
        demographics = demographics ?? FakeDemographicsRepository(form: sampleForm),
        dataExport = FakeDataExportRepository() {
    auth = AuthController(authRepository);
  }

  final FakeAuthRepository authRepository;
  late final AuthController auth;
  final FakeHomeRepository home;
  final FakeConsentRepository consent;
  final FakeProfileRepository profile;
  final FakeDemographicsRepository demographics;
  final FakeDataExportRepository dataExport;

  AppDependencies get dependencies => AppDependencies(
        auth: auth,
        home: home,
        consent: consent,
        profile: profile,
        demographics: demographics,
        dataExport: dataExport,
      );
}

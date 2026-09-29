import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:participant_app/app_dependencies.dart';
import 'package:participant_app/features/assignments/domain/assignments_repository.dart';
import 'package:participant_app/features/auth/application/auth_controller.dart';
import 'package:participant_app/features/auth/domain/auth_repository.dart';
import 'package:participant_app/features/auth/domain/auth_session.dart';
import 'package:participant_app/features/consent/domain/consent_repository.dart';
import 'package:participant_app/features/data_export/domain/data_export_repository.dart';
import 'package:participant_app/features/demographics/domain/demographics_repository.dart';
import 'package:participant_app/features/erase/domain/erase_repository.dart';
import 'package:participant_app/features/home/domain/home_repository.dart';
import 'package:participant_app/features/home/domain/participant_overview.dart';
import 'package:participant_app/features/profile/domain/profile_repository.dart';

import 'session_kit.dart';

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
  int loads = 0;

  @override
  Future<ParticipantOverview> loadOverview() async {
    loads++;
    return overview;
  }
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
  FakeDataExportRepository({Object? data}) : data = data ?? sampleMyData;

  Object? data;
  ApiException? failure;
  int fetches = 0;

  @override
  Future<Object?> fetchMyData() async {
    fetches++;
    if (failure != null) throw failure!;
    return data;
  }
}

/// What `/me/data` holds: two sessions with samples and events, two consents.
final Map<String, Object?> sampleMyData = {
  'participant': {'code': 'P-0001'},
  'consents': [
    {'sheet_version': 1, 'participate': true},
    {'sheet_version': 2, 'participate': true},
  ],
  'sessions': [
    {
      'summary': {'id': 1, 'status': 'ended'},
      'samples': [
        for (var i = 0; i < 5; i++) [i * 100, 700.0 + i, 300.0, 0.9, 2],
      ],
      'events': [
        {'t_ms': 0, 'type': 'segment_start', 'payload': {'segment': 'baseline'}},
        {'t_ms': 500, 'type': 'end', 'payload': {'reason': 'completed'}},
      ],
    },
    {
      'summary': {'id': 2, 'status': 'ended'},
      'samples': [
        for (var i = 0; i < 3; i++) [i * 100, null, null, 0.1, 4],
      ],
      'events': [
        {'t_ms': 0, 'type': 'segment_start', 'payload': {'segment': 'baseline'}},
      ],
    },
  ],
  'export_version': 2,
};

class FakeEraseRepository implements EraseRepository {
  ApiException? failure;
  String policy = RetentionPolicy.deleteAll;
  final List<String> confirmations = [];

  @override
  Future<EraseResult> eraseMyData(String confirm) async {
    confirmations.add(confirm);
    if (failure != null) throw failure!;
    return EraseResult(
      policy: policy,
      deleted: const {'sessions': 2, 'samples': 8},
      identityRemoved: true,
    );
  }
}

/// Remembers what was handed to the browser as a download.
class RecordingFileSaver {
  RecordingFileSaver({this.succeeds = true});

  final bool succeeds;
  final List<({String name, String type, Uint8List bytes})> saved = [];

  Future<bool> call(Uint8List bytes, String filename, String mimeType) async {
    if (succeeds) saved.add((name: filename, type: mimeType, bytes: bytes));
    return succeeds;
  }
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

class FakeAssignmentsRepository implements AssignmentsRepository {
  FakeAssignmentsRepository({List<Assignment>? items, PersonalizedContent? content})
      : items = items ?? [],
        contentValue = content;

  List<Assignment> items;
  PersonalizedContent? contentValue;
  ApiException? submitFailure;
  final List<({String id, String topic, String? freeText})> submitted = [];
  int contentCalls = 0;

  @override
  Future<List<Assignment>> list() async => List.of(items);

  @override
  Future<Assignment> submitTopic(
    String assignmentId, {
    required String topic,
    String? freeText,
  }) async {
    if (submitFailure != null) throw submitFailure!;
    submitted.add((id: assignmentId, topic: topic, freeText: freeText));
    final old = items.firstWhere((a) => a.id == assignmentId);
    final next = Assignment(
      id: old.id,
      orderIndex: old.orderIndex,
      status: AssignmentStatus.contentPending,
      protocol: old.protocol,
      topic: topic,
      topicFreeText: freeText,
    );
    items = [for (final a in items) a.id == assignmentId ? next : a];
    return next;
  }

  @override
  Future<PersonalizedContent> content(String assignmentId) async {
    contentCalls++;
    final c = contentValue;
    if (c == null) throw const ApiException('Not found.', statusCode: 404);
    return c;
  }
}

class TestBed {
  TestBed({
    FakeHomeRepository? home,
    FakeConsentRepository? consent,
    FakeProfileRepository? profile,
    FakeDemographicsRepository? demographics,
    FakeSessionRepository? sessions,
    FakeAssignmentsRepository? assignments,
    VideoStageBuilder? videoStage,
    FakeDataExportRepository? dataExport,
    FakeEraseRepository? erase,
    bool canSaveFiles = true,
  })  : authRepository = FakeAuthRepository(),
        erase = erase ?? FakeEraseRepository(),
        saver = RecordingFileSaver(succeeds: canSaveFiles),
        assignments = assignments ?? FakeAssignmentsRepository(),
        videoStage = videoStage ?? FakeVideoStage.builder(),
        home = home ?? FakeHomeRepository(),
        consent = consent ?? FakeConsentRepository(),
        profile = profile ?? FakeProfileRepository(),
        demographics = demographics ?? FakeDemographicsRepository(form: sampleForm),
        dataExport = dataExport ?? FakeDataExportRepository(),
        sessions = sessions ?? FakeSessionRepository(),
        gaze = FakeGazeEstimator(),
        frameSource = FakeFrameSource() {
    auth = AuthController(authRepository);
  }

  final FakeAuthRepository authRepository;
  late final AuthController auth;
  final FakeHomeRepository home;
  final FakeConsentRepository consent;
  final FakeProfileRepository profile;
  final FakeDemographicsRepository demographics;
  final FakeDataExportRepository dataExport;
  final FakeEraseRepository erase;

  /// What the downloads handed to the browser.
  final RecordingFileSaver saver;
  final FakeSessionRepository sessions;
  final FakeAssignmentsRepository assignments;
  final VideoStageBuilder videoStage;
  final FakeGazeEstimator gaze;
  final FakeFrameSource frameSource;

  AppDependencies get dependencies => AppDependencies(
        auth: auth,
        home: home,
        consent: consent,
        profile: profile,
        demographics: demographics,
        dataExport: dataExport,
        sessions: sessions,
        gaze: gaze,
        frameSource: frameSource,
        device: const DeviceInfo(platform: 'web', userAgent: 'test-agent'),
        assignments: assignments,
        videoStage: videoStage,
        erase: erase,
        saveFile: saver.call,
      );
}

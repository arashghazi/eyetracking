import 'dart:async';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:research_admin/app_dependencies.dart';
import 'package:research_admin/features/assignments/domain/assignments_repository.dart';
import 'package:research_admin/features/auth/application/auth_controller.dart';
import 'package:research_admin/features/auth/domain/auth_repository.dart';
import 'package:research_admin/features/auth/domain/auth_session.dart';
import 'package:research_admin/features/content/domain/content_repository.dart';
import 'package:research_admin/features/content/domain/media_picker.dart';
import 'package:research_admin/features/demographics_form/domain/demographics_form_repository.dart';
import 'package:research_admin/features/information_sheet/domain/information_sheet_repository.dart';
import 'package:research_admin/features/invitations/domain/invitation.dart';
import 'package:research_admin/features/invitations/domain/invitations_repository.dart';
import 'package:research_admin/features/measurement_settings/domain/measurement_settings_repository.dart';
import 'package:research_admin/features/members/domain/members_repository.dart';
import 'package:research_admin/features/participants/domain/participants_repository.dart';
import 'package:research_admin/features/protocols/domain/protocols_repository.dart';
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

/// A session of the gradual face path: two stages, twelve trials and
/// outcomes that cannot yet be judged.
final gradualSessionDetailJson = <String, dynamic>{
  ...sessionDetailJson,
  'assignment_id': 17,
  'protocol': {
    'id': 4,
    'name': 'Faces v1',
    'version': 2,
    'path': 'gradual_face',
    'definition': {
      'path': 'gradual_face',
      'baseline_seconds': 30,
      'post_seconds': 30,
      'comfort': {
        'scale_max': 5,
        'labels': ['Very uncomfortable', 'Uncomfortable', 'Neutral', 'Comfortable', 'Very comfortable'],
        'min_ok': 3,
        'ask_every_stage': true,
      },
      'gradual': {'stages': const []},
    },
  },
  'outcomes': {
    'gaze': {'baseline_eye_share': null, 'post_eye_share': null, 'evaluable': false, 'reason': 'synthetic_estimator'},
    'comprehension': {'answered': 0, 'correct': 0, 'share': null},
    'number_task': {'trials': 12, 'correct': 10, 'share': 0.83, 'stages_completed': 2},
    'comfort': {'answers': 3, 'min': 3, 'mean': 3.67, 'low_count': 0, 'pauses': 1, 'ended_early': false},
    'improvement': {
      'eligible': false,
      'result': null,
      'criteria': {'eye_share_up': null, 'comfort_not_worse': null, 'comprehension_maintained': null},
      'reason': 'synthetic_estimator',
    },
  },
  'stages': [
    {'stage_index': 0, 'decision': 'advance', 'reason': 'criteria_met', 'correct_ratio': 0.83, 'invalid_share': 0.05, 'comfort_value': 4, 'trials': 6},
    {'stage_index': 1, 'decision': 'complete', 'reason': 'all_stages_done', 'correct_ratio': 0.83, 'invalid_share': 0.1, 'comfort_value': 3, 'trials': 6},
  ],
  'trials': [
    for (var i = 0; i < 120; i++)
      {
        'stage_index': i ~/ 60,
        'trial_index': i % 60,
        't_ms': 40000 + i * 3000,
        'number_shown': '${10 + i % 80}',
        'zone': i < 60 ? 'outside' : 'face_edge',
        'position': {'x': 100, 'y': 200},
        'face_level': i < 60 ? 0 : 1,
        'response': i % 7 == 0 ? null : '${10 + i % 80}',
        'response_ms': i % 7 == 0 ? null : 800 + i,
        'correct': i % 7 != 0,
      },
  ],
  'answers': const [],
  'comfort_answers': [
    {'t_ms': 60000, 'payload': {'value': 4, 'stage_index': 0}},
    {'t_ms': 90000, 'payload': {'value': 3, 'stage_index': 1}},
    {'t_ms': 130000, 'payload': {'value': 5, 'segment': 'post'}},
  ],
};

/// A session of the interest path with a decided improvement.
final interestSessionDetailJson = <String, dynamic>{
  ...sessionDetailJson,
  'synthetic': false,
  'assignment_id': 18,
  'protocol': {
    'id': 5,
    'name': 'Trains talk',
    'version': 1,
    'path': 'interest_conversation',
  },
  'eye_region_attention': {'evaluable': true, 'share': 0.4, 'reason': null},
  'outcomes': {
    'gaze': {'baseline_eye_share': 0.2, 'post_eye_share': 0.4, 'evaluable': true, 'reason': null},
    'comprehension': {'answered': 4, 'correct': 3, 'share': 0.75},
    'number_task': {'trials': 0, 'correct': 0, 'share': null, 'stages_completed': 0},
    'comfort': {'answers': 2, 'min': 4, 'mean': 4.5, 'low_count': 0, 'pauses': 0, 'ended_early': false},
    'improvement': {
      'eligible': true,
      'result': true,
      'criteria': {'eye_share_up': true, 'comfort_not_worse': true, 'comprehension_maintained': true},
      'reason': null,
    },
  },
  'stages': const [],
  'trials': const [],
  'answers': [
    {'segment_id': 's1', 'question_id': 'q1', 'kind': 'interaction', 'option': 'Trains', 'correct': null, 't_ms': 30000, 'next_segment_id': 's2'},
    {'segment_id': 's2', 'question_id': 'c1', 'kind': 'comprehension', 'option': 'Red', 'correct': true, 't_ms': 52000, 'next_segment_id': null},
    {'segment_id': 's2', 'question_id': 'c2', 'kind': 'comprehension', 'option': 'Rome', 'correct': false, 't_ms': 60000, 'next_segment_id': null},
  ],
  'comfort_answers': [
    {'t_ms': 90000, 'payload': {'value': 4, 'segment': 'post'}},
  ],
};

class FakeSessionsRepository implements SessionsRepository {
  FakeSessionsRepository({
    this.items = sessionItems,
    this.sampleTotal = 250,
    this.detailJson,
  });

  List<SessionListItem> items;

  /// The detail the fake returns; the measurement-only session by default.
  Map<String, dynamic>? detailJson;
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
      SessionDetail.fromJson(detailJson ?? sessionDetailJson);

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

// ------------------------------------------------------------------ step 3

ProtocolSummary protocolRow(
  String id,
  String name, {
  int version = 0,
  String status = ProtocolStatus.draft,
  ProtocolPath path = ProtocolPath.gradualFace,
}) =>
    ProtocolSummary(
      id: id,
      name: name,
      version: version,
      status: status,
      path: path,
      createdAt: '2026-09-29T08:00:00',
      publishedAt: status == ProtocolStatus.published ? '2026-09-30T09:00:00' : null,
    );

class FakeProtocolsRepository implements ProtocolsRepository {
  FakeProtocolsRepository({List<ProtocolDetail>? items})
      : items = items ??
            [
              ProtocolDetail(
                summary: protocolRow('1', 'Faces v1',
                    version: 1, status: ProtocolStatus.published),
                definition: ProtocolDefinition.starter(ProtocolPath.gradualFace),
              ),
              ProtocolDetail(
                summary: protocolRow('2', 'Faces v2 draft'),
                definition: ProtocolDefinition.starter(ProtocolPath.gradualFace),
              ),
              ProtocolDetail(
                summary: protocolRow('3', 'Trains talk',
                    version: 1,
                    status: ProtocolStatus.published,
                    path: ProtocolPath.interestConversation),
                definition:
                    ProtocolDefinition.starter(ProtocolPath.interestConversation),
              ),
            ];

  List<ProtocolDetail> items;

  /// Thrown by create, update and publish when set.
  ApiException? writeFailure;
  final List<({String name, Map<String, dynamic> definition})> created = [];
  final List<({String id, String? name, Map<String, dynamic>? definition})>
      updated = [];
  final List<String> published = [];
  final List<String> newDrafts = [];

  ProtocolDetail _find(String id) => items.firstWhere((p) => p.summary.id == id);

  @override
  Future<List<ProtocolSummary>> list(int studyId) async =>
      [for (final p in items) p.summary];

  @override
  Future<ProtocolDetail> get(int studyId, String protocolId) async =>
      _find(protocolId);

  @override
  Future<ProtocolDetail> create(
    int studyId,
    String name,
    ProtocolDefinition definition,
  ) async {
    if (writeFailure != null) throw writeFailure!;
    created.add((name: name, definition: definition.toJson()));
    final detail = ProtocolDetail(
      summary: protocolRow('${items.length + 10}', name, path: definition.path),
      definition: definition,
    );
    items = [...items, detail];
    return detail;
  }

  @override
  Future<ProtocolDetail> update(
    int studyId,
    String protocolId, {
    String? name,
    ProtocolDefinition? definition,
  }) async {
    if (writeFailure != null) throw writeFailure!;
    updated.add((id: protocolId, name: name, definition: definition?.toJson()));
    final old = _find(protocolId);
    if (old.summary.isPublished) {
      throw const ApiException(
        'published protocol versions cannot be edited; create a new draft',
        statusCode: 409,
      );
    }
    final next = ProtocolDetail(
      summary: protocolRow(protocolId, name ?? old.summary.name,
          path: definition?.path ?? old.summary.path!),
      definition: definition ?? old.definition,
    );
    items = [for (final p in items) p.summary.id == protocolId ? next : p];
    return next;
  }

  @override
  Future<ProtocolDetail> publish(int studyId, String protocolId) async {
    if (writeFailure != null) throw writeFailure!;
    published.add(protocolId);
    final old = _find(protocolId);
    final next = ProtocolDetail(
      summary: protocolRow(protocolId, old.summary.name,
          version: 1, status: ProtocolStatus.published, path: old.summary.path!),
      definition: old.definition,
    );
    items = [for (final p in items) p.summary.id == protocolId ? next : p];
    return next;
  }

  @override
  Future<ProtocolDetail> newDraft(int studyId, String protocolId) async {
    newDrafts.add(protocolId);
    final old = _find(protocolId);
    final draft = ProtocolDetail(
      summary: protocolRow('${items.length + 20}', old.summary.name,
          path: old.summary.path!),
      definition: old.definition,
    );
    items = [...items, draft];
    return draft;
  }
}

ContentDefinition sampleContentDefinition() => const ContentDefinition(
      startSegment: 's1',
      postSegment: 's2',
      segments: [
        ContentSegment(
          id: 's1',
          text: 'Hi {{display_name}}, today we talk about {{topic}}.',
          mediaKey: 's1.webm',
          durationS: 20,
          faceLayout: NormalizedFaceLayout(
            faceBox: Box(0.3, 0.1, 0.4, 0.8),
            eyeRegion: Box(0.3, 0.25, 0.4, 0.2),
            mouthRegion: Box(0.3, 0.55, 0.4, 0.25),
          ),
          question: ContentQuestion(
            id: 'q1',
            prompt: 'Which do you prefer?',
            options: ['Trains', 'Planes'],
            branches: {'Trains': 's2'},
          ),
        ),
        ContentSegment(id: 's2', mediaKey: 's2.webm', durationS: 15),
      ],
      comprehension: [
        ComprehensionItem(
          id: 'c1',
          prompt: 'What colour was the train?',
          options: ['Red', 'Blue'],
          correct: 'Red',
        ),
      ],
    );

class FakeContentRepository implements ContentRepository {
  FakeContentRepository({List<ContentDetail>? items})
      : items = items ??
            [
              ContentDetail(
                summary: const ContentSummary(
                  id: '1',
                  title: 'Trains, part one',
                  topicTags: ['trains', 'railways'],
                  faceId: 'f1',
                  voiceId: 'v1',
                  status: ContentStatus.approved,
                  mediaKeys: ['s1.webm', 's2.webm'],
                ),
                definition: sampleContentDefinition(),
              ),
              ContentDetail(
                summary: const ContentSummary(
                  id: '2',
                  title: 'Planes, draft',
                  topicTags: ['planes'],
                  faceId: 'f2',
                  voiceId: 'v1',
                  mediaKeys: ['s1.webm', 's2.webm'],
                  missingMedia: ['s2.webm'],
                ),
                definition: sampleContentDefinition(),
              ),
              ContentDetail(
                summary: const ContentSummary(
                  id: '3',
                  title: 'Space, approved',
                  topicTags: ['space'],
                  status: ContentStatus.approved,
                  mediaKeys: ['s1.webm', 's2.webm'],
                ),
                definition: sampleContentDefinition(),
              ),
            ];

  List<ContentDetail> items;
  ApiException? writeFailure;

  /// When set, approval answers with this (a 422 naming the missing media).
  ApiException? approveFailure;
  final List<Map<String, dynamic>> saved = [];
  final List<String> approved = [];
  final List<({String id, String key, String filename, String type, int size})>
      uploads = [];

  /// When set, an upload waits for it before it completes.
  Completer<void>? uploadGate;
  ApiException? uploadFailure;
  int uploadSteps = 4;

  ContentDetail _find(String id) => items.firstWhere((c) => c.summary.id == id);

  @override
  Future<List<ContentSummary>> list(int studyId) async =>
      [for (final c in items) c.summary];

  @override
  Future<ContentDetail> get(int studyId, String contentId) async =>
      _find(contentId);

  ContentDetail _store(
    String id, {
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
    List<String>? missing,
  }) {
    saved.add({
      'id': id,
      'title': title,
      'topic_tags': topicTags,
      'face_id': faceId,
      'voice_id': voiceId,
      'definition': definition.toJson(),
    });
    final keys = [
      for (final s in definition.segments)
        if (s.mediaKey.isNotEmpty) s.mediaKey,
    ];
    final old = items.where((c) => c.summary.id == id).firstOrNull;
    final detail = ContentDetail(
      summary: ContentSummary(
        id: id,
        title: title,
        topicTags: topicTags,
        faceId: faceId,
        voiceId: voiceId,
        mediaKeys: keys,
        missingMedia: missing ??
            [
              for (final k in keys)
                if (!(_uploadedKeys[id]?.contains(k) ?? false) &&
                    !(old?.summary.mediaKeys.contains(k) == true &&
                        old?.summary.missingMedia.contains(k) == false))
                  k,
            ],
      ),
      definition: definition,
    );
    items = [
      for (final c in items)
        if (c.summary.id != id) c,
      detail,
    ];
    return detail;
  }

  final Map<String, Set<String>> _uploadedKeys = {};

  @override
  Future<ContentDetail> create(
    int studyId, {
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
  }) async {
    if (writeFailure != null) throw writeFailure!;
    return _store('${items.length + 10}',
        title: title,
        topicTags: topicTags,
        faceId: faceId,
        voiceId: voiceId,
        definition: definition);
  }

  @override
  Future<ContentDetail> update(
    int studyId,
    String contentId, {
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
  }) async {
    if (writeFailure != null) throw writeFailure!;
    return _store(contentId,
        title: title,
        topicTags: topicTags,
        faceId: faceId,
        voiceId: voiceId,
        definition: definition);
  }

  @override
  Future<ContentDetail> approve(int studyId, String contentId) async {
    if (approveFailure != null) throw approveFailure!;
    approved.add(contentId);
    final old = _find(contentId);
    final next = ContentDetail(
      summary: ContentSummary(
        id: old.summary.id,
        title: old.summary.title,
        topicTags: old.summary.topicTags,
        faceId: old.summary.faceId,
        voiceId: old.summary.voiceId,
        status: ContentStatus.approved,
        mediaKeys: old.summary.mediaKeys,
      ),
      definition: old.definition,
    );
    items = [for (final c in items) c.summary.id == contentId ? next : c];
    return next;
  }

  @override
  Future<MediaInfo> uploadMedia(
    int studyId,
    String contentId,
    String key, {
    required Uint8List bytes,
    required String filename,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (uploadFailure != null) throw uploadFailure!;
    final total = bytes.length;
    for (var i = 1; i <= uploadSteps; i++) {
      onProgress?.call(total * i ~/ uploadSteps, total);
      if (i == uploadSteps ~/ 2 && uploadGate != null) await uploadGate!.future;
    }
    uploads.add((
      id: contentId,
      key: key,
      filename: filename,
      type: contentType,
      size: total,
    ));
    (_uploadedKeys[contentId] ??= {}).add(key);
    return MediaInfo(key: key, contentType: contentType, size: total);
  }

  @override
  Future<List<MediaInfo>> media(int studyId, String contentId) async => [
        for (final k in _uploadedKeys[contentId] ?? <String>{}) MediaInfo(key: k),
      ];
}

class FakeMediaPicker implements MediaPicker {
  /// What the next dialog returns; null means the dialog was cancelled.
  PickedMedia? next = PickedMedia(
    name: 's2.webm',
    bytes: Uint8List(2000),
    contentType: 'video/webm',
  );
  final List<String> accepts = [];

  @override
  Future<PickedMedia?> pick({String accept = ''}) async {
    accepts.add(accept);
    return next;
  }
}

Assignment assignmentRow(
  String id,
  String status, {
  int order = 0,
  String protocol = 'Trains talk',
  ProtocolPath path = ProtocolPath.interestConversation,
  String? topic,
  String? contentTitle,
}) =>
    Assignment(
      id: id,
      orderIndex: order,
      status: status,
      protocol: ProtocolRef(id: '3', name: protocol, version: 1, path: path),
      topic: topic,
      contentTitle: contentTitle,
    );

class FakeAssignmentsRepository implements AssignmentsRepository {
  FakeAssignmentsRepository({List<Assignment>? items}) : items = items ?? [];

  List<Assignment> items;
  ApiException? failure;
  final List<({String code, String protocolId, int? order})> created = [];
  final List<({String id, String contentId})> attached = [];
  final List<String> cancelled = [];

  @override
  Future<List<Assignment>> list(int studyId, String code) async => List.of(items);

  @override
  Future<Assignment> create(
    int studyId,
    String code, {
    required String protocolId,
    int? orderIndex,
  }) async {
    if (failure != null) throw failure!;
    created.add((code: code, protocolId: protocolId, order: orderIndex));
    final a = assignmentRow(
      '${items.length + 50}',
      protocolId == '3'
          ? AssignmentStatus.pendingTopic
          : AssignmentStatus.ready,
      order: orderIndex ?? items.length,
      protocol: protocolId == '3' ? 'Trains talk' : 'Faces v1',
      path: protocolId == '3'
          ? ProtocolPath.interestConversation
          : ProtocolPath.gradualFace,
    );
    items = [...items, a];
    return a;
  }

  @override
  Future<Assignment> attachContent(
    int studyId,
    String code,
    String assignmentId,
    String contentId,
  ) async {
    if (failure != null) throw failure!;
    attached.add((id: assignmentId, contentId: contentId));
    final old = items.firstWhere((a) => a.id == assignmentId);
    final next = Assignment(
      id: old.id,
      orderIndex: old.orderIndex,
      status: AssignmentStatus.ready,
      protocol: old.protocol,
      topic: old.topic,
      contentId: contentId,
      contentTitle: 'Attached content',
    );
    items = [for (final a in items) a.id == assignmentId ? next : a];
    return next;
  }

  @override
  Future<Assignment> cancel(int studyId, String code, String assignmentId) async {
    cancelled.add(assignmentId);
    final old = items.firstWhere((a) => a.id == assignmentId);
    final next = Assignment(
      id: old.id,
      orderIndex: old.orderIndex,
      status: AssignmentStatus.cancelled,
      protocol: old.protocol,
    );
    items = [for (final a in items) a.id == assignmentId ? next : a];
    return next;
  }
}

class TestBed {
  TestBed({
    FakeParticipantsRepository? participants,
    FakeInformationSheetRepository? informationSheet,
    FakeDemographicsFormRepository? demographicsForm,
    FakeSessionsRepository? sessions,
    FakeMeasurementSettingsRepository? measurementSettings,
    FakeProtocolsRepository? protocols,
    FakeContentRepository? content,
    FakeAssignmentsRepository? assignments,
    FakeMediaPicker? mediaPicker,
  })  : authRepository = FakeAuthRepository(),
        protocols = protocols ?? FakeProtocolsRepository(),
        content = content ?? FakeContentRepository(),
        assignments = assignments ?? FakeAssignmentsRepository(),
        mediaPicker = mediaPicker ?? FakeMediaPicker(),
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
  final FakeProtocolsRepository protocols;
  final FakeContentRepository content;
  final FakeAssignmentsRepository assignments;
  final FakeMediaPicker mediaPicker;

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
        protocols: protocols,
        content: content,
        assignments: assignments,
        mediaPicker: mediaPicker,
      );
}

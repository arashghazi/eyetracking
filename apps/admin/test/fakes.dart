import 'dart:async';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:research_admin/app_dependencies.dart';
import 'package:research_admin/features/access_log/domain/access_log_repository.dart';
import 'package:research_admin/features/ai/domain/ai_repository.dart';
import 'package:research_admin/features/analysis/domain/analysis_filters.dart';
import 'package:research_admin/features/analysis/domain/analysis_repository.dart';
import 'package:research_admin/features/assignments/domain/assignments_repository.dart';
import 'package:research_admin/features/auth/application/auth_controller.dart';
import 'package:research_admin/features/auth/domain/auth_repository.dart';
import 'package:research_admin/features/auth/domain/auth_session.dart';
import 'package:research_admin/features/content/domain/content_repository.dart';
import 'package:research_admin/features/content/domain/media_picker.dart';
import 'package:research_admin/features/demographics_form/domain/demographics_form_repository.dart';
import 'package:research_admin/features/exports/domain/exports_repository.dart';
import 'package:research_admin/features/information_sheet/domain/information_sheet_repository.dart';
import 'package:research_admin/features/invitations/domain/invitation.dart';
import 'package:research_admin/features/invitations/domain/invitations_repository.dart';
import 'package:research_admin/features/measurement_settings/domain/measurement_settings_repository.dart';
import 'package:research_admin/features/members/domain/members_repository.dart';
import 'package:research_admin/features/participants/domain/participants_repository.dart';
import 'package:research_admin/features/pilot/domain/pilot_repository.dart';
import 'package:research_admin/features/protocols/domain/protocols_repository.dart';
import 'package:research_admin/features/replay/domain/replay_repository.dart';
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
  final List<({int id, String policy})> policyChanges = [];
  ApiException? policyFailure;

  /// Thrown by [get] when set (a 403 for an admin who is not a member).
  ApiException? getFailure;

  @override
  Future<List<Study>> list() async => List.of(studies);

  @override
  Future<Study> get(int studyId) async {
    if (getFailure != null) throw getFailure!;
    return studies.firstWhere((s) => s.id == studyId);
  }

  @override
  Future<Study> setRetentionPolicy(int studyId, String policy) async {
    if (policyFailure != null) throw policyFailure!;
    policyChanges.add((id: studyId, policy: policy));
    final next = studies.firstWhere((s) => s.id == studyId).copyWith(retentionPolicy: policy);
    studies[studies.indexWhere((s) => s.id == studyId)] = next;
    return next;
  }

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
  ApiException? deleteFailure;
  final List<({String code, String confirm})> deletions = [];

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

  @override
  Future<EraseResult> deleteData(int studyId, String code, String confirm) async {
    if (deleteFailure != null) throw deleteFailure!;
    deletions.add((code: code, confirm: confirm));
    // What is left is an empty record: no consent, profile or demographics.
    records = [
      for (final r in records)
        if (r.code == code)
          ParticipantRecord(
            code: code,
            readiness: const Readiness(ready: false, reasons: [
              ReadinessReason.consentMissingOrOutdated,
              ReadinessReason.demographicsIncomplete,
            ]),
          )
        else
          r,
    ];
    return const EraseResult(deleted: {'sessions': 2, 'samples': 900});
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
    quality: SessionQuality(
      grade: QualityGrade.exclude,
      reasons: ['synthetic_estimator', 'validation_not_passed'],
    ),
  ),
  SessionListItem(
    id: '22',
    participantCode: 'P-002',
    status: SessionStatus.calibrated,
    createdAt: '2026-09-30T09:30:00',
    calibrationResidualPx: 52,
    quality: SessionQuality(
      grade: QualityGrade.review,
      reasons: ['ended_early', 'uncertain_share_above_0.2'],
    ),
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
    quality: SessionQuality(grade: QualityGrade.ok),
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
  'quality': {
    'grade': 'exclude',
    'reasons': ['synthetic_estimator', 'validation_not_passed'],
  },
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

/// The eight values of [s] as the settings history shows them.
SettingsValues settingsValuesOf(MeasurementSettings s) => SettingsValues(
      validationMinCorrect: s.validationMinCorrect,
      validationMaxUncertain: s.validationMaxUncertain,
      minRegionToErrorRatio: s.minRegionToErrorRatio,
      gazeConfThreshold: s.gazeConfThreshold,
      calibrationPoints: s.calibrationPoints,
      allowContinueWithoutValidation: s.allowContinueWithoutValidation,
      qualityMaxUncertainShare: s.qualityMaxUncertainShare,
      qualityMaxMissingShare: s.qualityMaxMissingShare,
    );

class FakeMeasurementSettingsRepository
    implements MeasurementSettingsRepository {
  MeasurementSettings settings = MeasurementSettings.defaults;

  /// Every settings object saved through [save].
  final List<MeasurementSettings> saved = [];

  /// The rationale of every save (null when none was given).
  final List<String?> rationales = [];

  /// Partial saves (a threshold review's changes) with their rationale.
  final List<({Map<String, dynamic> changes, String? rationale})> changeSaves = [];
  ApiException? saveFailure;

  /// The settings versions, newest first; a real change adds one.
  List<SettingsVersion> history = [
    const SettingsVersion(
      version: 1,
      rationale: 'Defaults; no change recorded yet',
    ),
  ];

  @override
  Future<MeasurementSettings> load(int studyId) async => settings;

  MeasurementSettings _store(MeasurementSettings next, String? rationale) {
    final changed = settingsValuesOf(next).changesFrom(settingsValuesOf(settings)).isNotEmpty;
    var version = settings.version;
    if (changed) {
      version++;
      history = [
        SettingsVersion(
          version: version,
          values: settingsValuesOf(next),
          rationale: rationale ?? '',
          changedBy: 7,
          createdAt: '2026-09-30T12:00:00',
        ),
        ...history,
      ];
    }
    return settings = MeasurementSettings(
      validationMinCorrect: next.validationMinCorrect,
      validationMaxUncertain: next.validationMaxUncertain,
      minRegionToErrorRatio: next.minRegionToErrorRatio,
      gazeConfThreshold: next.gazeConfThreshold,
      calibrationPoints: next.calibrationPoints,
      allowContinueWithoutValidation: next.allowContinueWithoutValidation,
      qualityMaxUncertainShare: next.qualityMaxUncertainShare,
      qualityMaxMissingShare: next.qualityMaxMissingShare,
      version: version,
    );
  }

  @override
  Future<MeasurementSettings> save(
    int studyId,
    MeasurementSettings next, {
    String? rationale,
  }) async {
    if (saveFailure != null) throw saveFailure!;
    saved.add(next);
    rationales.add(rationale);
    // The form does not send the quality thresholds; they keep their values.
    return _store(
      MeasurementSettings(
        validationMinCorrect: next.validationMinCorrect,
        validationMaxUncertain: next.validationMaxUncertain,
        minRegionToErrorRatio: next.minRegionToErrorRatio,
        gazeConfThreshold: next.gazeConfThreshold,
        calibrationPoints: next.calibrationPoints,
        allowContinueWithoutValidation: next.allowContinueWithoutValidation,
        qualityMaxUncertainShare: settings.qualityMaxUncertainShare,
        qualityMaxMissingShare: settings.qualityMaxMissingShare,
      ),
      rationale,
    );
  }

  @override
  Future<MeasurementSettings> saveChanges(
    int studyId,
    Map<String, dynamic> changes, {
    String? rationale,
  }) async {
    if (saveFailure != null) throw saveFailure!;
    changeSaves.add((changes: Map.of(changes), rationale: rationale));
    double d(String key, double current) =>
        (changes[key] as num?)?.toDouble() ?? current;
    final s = settings;
    return _store(
      MeasurementSettings(
        validationMinCorrect: d('validation_min_correct', s.validationMinCorrect),
        validationMaxUncertain:
            d('validation_max_uncertain', s.validationMaxUncertain),
        minRegionToErrorRatio:
            d('min_region_to_error_ratio', s.minRegionToErrorRatio),
        gazeConfThreshold: d('gaze_conf_threshold', s.gazeConfThreshold),
        calibrationPoints: s.calibrationPoints,
        allowContinueWithoutValidation: s.allowContinueWithoutValidation,
        qualityMaxUncertainShare:
            d('quality_max_uncertain_share', s.qualityMaxUncertainShare),
        qualityMaxMissingShare:
            d('quality_max_missing_share', s.qualityMaxMissingShare),
      ),
      rationale,
    );
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

  /// When set, marking the text as reviewed answers with this.
  ApiException? reviewFailure;
  final List<String> reviewed = [];
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
        textReviewed: old.summary.textReviewed,
      ),
      definition: old.definition,
    );
    items = [for (final c in items) c.summary.id == contentId ? next : c];
    return next;
  }

  @override
  Future<ContentDetail> markTextReviewed(int studyId, String contentId) async {
    if (reviewFailure != null) throw reviewFailure!;
    reviewed.add(contentId);
    final old = _find(contentId);
    final s = old.summary;
    final next = ContentDetail(
      summary: ContentSummary(
        id: s.id,
        title: s.title,
        topicTags: s.topicTags,
        faceId: s.faceId,
        voiceId: s.voiceId,
        status: s.status,
        mediaKeys: s.mediaKeys,
        missingMedia: s.missingMedia,
        textReviewed: true,
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

  /// When set, listing the assignments answers with this (unknown code).
  ApiException? listFailure;
  final List<String> listedCodes = [];
  final List<({String code, String protocolId, int? order})> created = [];
  final List<({String id, String contentId})> attached = [];
  final List<String> cancelled = [];

  @override
  Future<List<Assignment>> list(int studyId, String code) async {
    listedCodes.add(code);
    if (listFailure != null) throw listFailure!;
    return List.of(items);
  }

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
    FakeReplayRepository? replay,
    FakeAnalysisRepository? analysis,
    FakeExportsRepository? exports,
    FakeAccessLogRepository? accessLog,
    FakeAiRepository? ai,
    FakePilotRepository? pilot,
    FakeStudiesRepository? studies,
    bool canSaveFiles = true,
  })  : authRepository = FakeAuthRepository(),
        ai = ai ?? FakeAiRepository(),
        replay = replay ?? FakeReplayRepository(),
        analysis = analysis ?? FakeAnalysisRepository(),
        exports = exports ?? FakeExportsRepository(),
        accessLog = accessLog ?? FakeAccessLogRepository(),
        saver = RecordingFileSaver(succeeds: canSaveFiles),
        protocols = protocols ?? FakeProtocolsRepository(),
        content = content ?? FakeContentRepository(),
        assignments = assignments ?? FakeAssignmentsRepository(),
        mediaPicker = mediaPicker ?? FakeMediaPicker(),
        studies = studies ?? FakeStudiesRepository(),
        participants = participants ?? FakeParticipantsRepository(),
        invitations = FakeInvitationsRepository(),
        informationSheet = informationSheet ?? FakeInformationSheetRepository(),
        demographicsForm = demographicsForm ?? FakeDemographicsFormRepository(),
        members = FakeMembersRepository(),
        sessions = sessions ?? FakeSessionsRepository(),
        measurementSettings =
            measurementSettings ?? FakeMeasurementSettingsRepository() {
    this.pilot = pilot ?? FakePilotRepository(settings: this.measurementSettings);
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
  final FakeReplayRepository replay;
  final FakeAnalysisRepository analysis;
  final FakeExportsRepository exports;
  final FakeAccessLogRepository accessLog;
  final FakeAiRepository ai;
  late final FakePilotRepository pilot;

  /// The AI tab's auto-refresh timers and the live monitor's polling timers,
  /// fired by hand.
  final List<ManualTimer> timers = [];

  /// What the downloads handed to the browser.
  final RecordingFileSaver saver;

  /// What the replay asked of the stimulus video.
  final RecordingVideoPlayer videoPlayer = RecordingVideoPlayer();

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
        replay: replay,
        analysis: analysis,
        exports: exports,
        accessLog: accessLog,
        videoStage: FakeVideoStage.builder(player: videoPlayer),
        saveFile: saver.call,
        ai: ai,
        pilot: pilot,
        schedule: (d, f) {
          final t = ManualTimer(d, f);
          timers.add(t);
          return t;
        },
      );
}


// ------------------------------------------------------------------ step 4

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

const _layout = {
  'screen': {'w': 1440, 'h': 900, 'dpr': 1},
  'face_box': [500, 100, 440, 600],
  'eye_region': [520, 220, 400, 120],
  'mouth_region': [560, 480, 320, 100],
};

/// A replay of 30 s: baseline 1-11 s, practice 12-30 s with two trials, a
/// gap, a pause, and a stimulus clip from 12 s.
Map<String, dynamic> sampleReplayJson({bool withMedia = true}) => {
      'session': {
        'id': 21,
        'participant_code': 'P-001',
        'status': 'ended',
        'created_at': '2026-09-29T08:00:00',
        'synthetic': true,
        'quality': {
          'grade': 'review',
          'reasons': ['validation_not_passed', 'uncertain_share_above_0.2'],
        },
        'protocol': {'name': 'Faces v1', 'version': 2, 'path': 'gradual_face'},
      },
      'screen': {'w': 1440, 'h': 900, 'dpr': 1},
      'segments': [
        {'label': 'baseline', 'started_ms': 1000, 'ended_ms': 11000},
        {'label': 'practice', 'started_ms': 12000, 'ended_ms': 30000},
      ],
      'layouts': [
        {'id': 1, 'segment': 'baseline', 'stage_index': null, 'layout': _layout, 'from_ms': 1000, 'to_ms': 9000},
        {'id': 2, 'segment': 'practice', 'stage_index': 0, 'layout': _layout, 'from_ms': 12000, 'to_ms': 30000},
      ],
      'samples': [
        for (var t = 1000; t <= 9000; t += 100)
          [t, 700.0 + (t - 1000) / 50, 300.0, 0.9, t % 300 == 0 ? 0 : 2],
        [9100, null, null, 0.1, 4],
        for (var t = 12000; t <= 30000; t += 100)
          [t, 720.0, 340.0 + (t - 12000) / 100, 0.8, 1],
      ],
      'events': [
        {'t_ms': 1000, 'type': 'segment_start', 'payload': {'segment': 'baseline'}},
        {'t_ms': 20500, 'type': 'pause', 'payload': null},
      ],
      'trials': [
        {'stage_index': 0, 'trial_index': 0, 't_ms': 13000, 'number_shown': '42', 'zone': 'outside', 'position': {'x': 200, 'y': 150}, 'face_level': 0, 'response': '42', 'correct': true, 'response_ms': 1500},
        {'stage_index': 0, 'trial_index': 1, 't_ms': 16000, 'number_shown': '17', 'zone': 'outside', 'position': {'x': 1200, 'y': 700}, 'face_level': 0, 'response': null, 'correct': null, 'response_ms': null},
      ],
      'answers': const [],
      'quality_strip': [
        for (var i = 0; i < 30; i++)
          {'from_ms': i * 1000, 'to_ms': (i + 1) * 1000, 'valid_share': i == 10 ? null : (i % 5) / 5 + 0.1},
      ],
      'gaps': [
        {'from_ms': 9200, 'to_ms': 11900},
      ],
      'pauses': [
        {'from_ms': 20500, 'to_ms': 22000},
      ],
      'media': withMedia
          ? [
              {'segment_id': 's1', 'media_key': 's1.webm', 'start_ms': 12000, 'url': '/media/tok1'},
              {'segment_id': 's2', 'media_key': 's2.webm', 'start_ms': 22000, 'url': '/media/tok2'},
            ]
          : const [],
    };

class FakeReplayRepository implements ReplayRepository {
  FakeReplayRepository({Map<String, dynamic>? json}) : json = json ?? sampleReplayJson();

  Map<String, dynamic> json;
  ApiException? failure;
  final List<String> loaded = [];

  @override
  Future<ReplayBundle> load(int studyId, String sessionId) async {
    if (failure != null) throw failure!;
    loaded.add('$studyId/$sessionId');
    return ReplayBundle.fromJson(json);
  }
}

/// Two comparable groups, three sessions of P-001 (one not evaluable) and one
/// of P-002.
Map<String, dynamic> sampleAnalysisJson() => {
      'filters': {'include_synthetic': false, 'quality': 'ok,review'},
      'rows': [
        {
          'session_id': 5,
          'participant_code': 'P-001',
          'created_at': '2026-09-29T08:00:00',
          'path': 'gradual_face',
          'protocol_name': 'Faces v1',
          'protocol_version': 2,
          'device_platform': 'web',
          'estimator': 'l2cs-1',
          'synthetic': false,
          'quality': 'ok',
          'quality_reasons': [],
          'calibration_residual_px': 41.2,
          'validation_passed': true,
          'total_ms': 120000,
          'classifiable_share': 0.9,
          'uncertain_share': 0.06,
          'missing_share': 0.04,
          'face_share': 0.7,
          'eye_share': 0.3,
          'baseline_eye_share': 0.2,
          'post_eye_share': 0.32,
          'eye_share_delta': 0.12,
          'comprehension_share': null,
          'number_task_share': 0.83,
          'stages_completed': 3,
          'comfort_min': 3,
          'comfort_mean': 4.0,
          'comfort_low_count': 0,
          'pauses': 1,
          'ended_early': false,
          'improvement': true,
          'group_key': 'web|2|l2cs-1|400',
          'demographics': {'age': 34},
        },
        {
          'session_id': 6,
          'participant_code': 'P-001',
          'created_at': '2026-10-02T08:00:00',
          'path': 'gradual_face',
          'protocol_name': 'Faces v1',
          'protocol_version': 2,
          'device_platform': 'web',
          'estimator': 'l2cs-1',
          'quality': 'review',
          'quality_reasons': ['ended_early'],
          'baseline_eye_share': 0.3,
          'post_eye_share': 0.24,
          'eye_share_delta': -0.06,
          'comfort_mean': 3.0,
          'ended_early': true,
          'improvement': false,
          'group_key': 'web|2|l2cs-1|400',
        },
        {
          'session_id': 7,
          'participant_code': 'P-001',
          'created_at': '2026-10-05T08:00:00',
          'path': 'gradual_face',
          'device_platform': 'web',
          'quality': 'review',
          'quality_reasons': ['validation_not_passed'],
          'baseline_eye_share': null,
          'post_eye_share': null,
          'eye_share_delta': null,
          'comfort_mean': 4.5,
          'group_key': 'web|2|l2cs-1|400',
        },
        {
          'session_id': 8,
          'participant_code': 'P-002',
          'created_at': '2026-10-06T08:00:00',
          'path': 'interest_conversation',
          'device_platform': 'android',
          'quality': 'ok',
          'quality_reasons': [],
          'baseline_eye_share': 0.2,
          'post_eye_share': 0.2,
          'eye_share_delta': 0.0,
          'group_key': 'android|1|l2cs-1|300',
        },
      ],
      'groups': [
        {'group_key': 'web|2|l2cs-1|400', 'device_platform': 'web', 'protocol_version': 2, 'estimator': 'l2cs-1', 'screen_bucket': '1280x720', 'stimulus_bucket_px': '400px', 'sessions': 3, 'participants': 1},
        {'group_key': 'android|1|l2cs-1|300', 'device_platform': 'android', 'protocol_version': 1, 'estimator': 'l2cs-1', 'screen_bucket': '360x740', 'stimulus_bucket_px': 300, 'sessions': 1, 'participants': 1},
      ],
      'trends': [
        {
          'participant_code': 'P-001',
          'group_key': 'web|2|l2cs-1|400',
          'points': [
            {'session_id': 7, 'created_at': '2026-10-05T08:00:00', 'baseline_eye_share': null, 'post_eye_share': null, 'comfort_mean': 4.5, 'quality': 'review'},
            {'session_id': 5, 'created_at': '2026-09-29T08:00:00', 'baseline_eye_share': 0.2, 'post_eye_share': 0.32, 'comfort_mean': 4.0, 'quality': 'ok'},
            {'session_id': 6, 'created_at': '2026-10-02T08:00:00', 'baseline_eye_share': 0.3, 'post_eye_share': 0.24, 'comfort_mean': 3.0, 'quality': 'review'},
          ],
        },
        {
          'participant_code': 'P-002',
          'group_key': 'android|1|l2cs-1|300',
          'points': [
            {'session_id': 8, 'created_at': '2026-10-06T08:00:00', 'baseline_eye_share': 0.2, 'post_eye_share': 0.2},
          ],
        },
      ],
      'excluded': 2,
      'note': 'Sessions from different groups are never pooled into one trend by default.',
    };

class FakeAnalysisRepository implements AnalysisRepository {
  FakeAnalysisRepository({Map<String, dynamic>? json}) : json = json ?? sampleAnalysisJson();

  Map<String, dynamic> json;
  ApiException? failure;
  final List<AnalysisFilters> requests = [];

  @override
  Future<AnalysisResponse> analysis(int studyId, AnalysisFilters filters) async {
    if (failure != null) throw failure!;
    requests.add(filters);
    return AnalysisResponse.fromJson(json);
  }
}

class FakeExportsRepository implements ExportsRepository {
  ApiException? failure;
  final List<String> calls = [];
  final List<AnalysisFilters> filters = [];
  List<DictionaryEntry> dictionary = const [
    DictionaryEntry(
      name: 'eye_share',
      type: 'float',
      unit: 'share 0-1',
      meaning: 'Share of classifiable time on the eye region.',
    ),
    DictionaryEntry(
      name: 'quality',
      type: 'string',
      unit: '-',
      meaning: 'ok, review or exclude.',
    ),
  ];

  Uint8List _bytes(String name) {
    if (failure != null) throw failure!;
    calls.add(name);
    return Uint8List.fromList('data:$name'.codeUnits);
  }

  @override
  Future<Uint8List> sessionsCsv(int studyId, AnalysisFilters f) async {
    filters.add(f);
    return _bytes('sessions.csv');
  }

  @override
  Future<Uint8List> sessionsJson(int studyId, AnalysisFilters f) async {
    filters.add(f);
    return _bytes('sessions.json');
  }

  @override
  Future<Uint8List> samplesCsv(int studyId, String sessionId) async =>
      _bytes('samples.csv:$sessionId');

  @override
  Future<Uint8List> eventsCsv(int studyId, String sessionId) async =>
      _bytes('events.csv:$sessionId');

  @override
  Future<List<DictionaryEntry>> dataDictionary(int studyId) async {
    if (failure != null) throw failure!;
    calls.add('dictionary');
    return dictionary;
  }
}

class FakeAccessLogRepository implements AccessLogRepository {
  FakeAccessLogRepository({List<AccessLogEntry>? entries})
      : entries = entries ??
            const [
              AccessLogEntry(
                at: '2026-09-30T09:15:00',
                userId: '4',
                role: 'researcher',
                action: 'export_sessions',
                detail: 'sessions.csv, 12 rows',
              ),
              AccessLogEntry(
                at: '2026-09-30T08:00:00',
                userId: '5',
                role: 'analyst',
                action: 'replay',
                detail: 'session_id: 21',
              ),
              AccessLogEntry(
                at: '2026-09-29T17:45:00',
                userId: '4',
                role: 'researcher',
                action: 'delete_participant_data',
              ),
            ];

  List<AccessLogEntry> entries;
  ApiException? failure;
  final List<int> limits = [];

  @override
  Future<List<AccessLogEntry>> list(int studyId, {int limit = 200}) async {
    if (failure != null) throw failure!;
    limits.add(limit);
    return entries;
  }
}


// ------------------------------------------------------------------ step 5

/// A timer that fires only when a test says so.
class ManualTimer implements Timer {
  ManualTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}

AiJob aiJob(
  String id, {
  String kind = AiJobKind.text,
  String status = AiJobStatus.succeeded,
  String provider = 'fake',
  String? contentId = '7',
  String? segmentId,
  int attempts = 1,
  double estimate = 0.1,
  double? actual,
  String? error,
}) =>
    AiJob(
      id: id,
      kind: kind,
      status: status,
      provider: provider,
      contentId: contentId,
      segmentId: segmentId,
      attempts: attempts,
      costEstimateUnits: estimate,
      costActualUnits: actual,
      error: error,
      createdAt: '2026-09-29T10:00:00',
    );

const configuredStatus = AiStatus(
  textProvider: AiProviderStatus(
    name: 'anthropic',
    model: 'claude-sonnet-x',
    configured: true,
  ),
  videoProvider: AiProviderStatus(name: 'heygen', configured: false),
  budget: AiBudget(costCapUnits: 10, spentUnits: 2.5, remainingUnits: 7.5),
  worker: AiWorkerStatus(enabled: true, intervalS: 30),
);

const syntheticStatus = AiStatus(
  textProvider: AiProviderStatus(
    name: 'fake',
    model: 'fake-text',
    configured: true,
    synthetic: true,
  ),
  videoProvider: AiProviderStatus(name: 'fake', configured: true, synthetic: true),
  budget: AiBudget(),
  worker: AiWorkerStatus(enabled: false, intervalS: 30),
);

class FakeAiRepository implements AiRepository {
  FakeAiRepository({AiStatus? status, List<AiJob>? jobs})
      : statusValue = status ?? syntheticStatus,
        jobList = jobs ?? [];

  AiStatus statusValue;
  List<AiJob> jobList;
  ApiException? statusFailure;
  ApiException? budgetFailure;
  ApiException? textJobFailure;
  ApiException? videoJobFailure;
  ApiException? actionFailure;

  final List<TextJobRequest> textRequests = [];
  final List<VideoJobRequest> videoRequests = [];
  final List<double> budgetChanges = [];
  final List<bool> freeTextChanges = [];
  final List<String> cancelled = [];
  final List<String> retried = [];
  final List<int> runs = [];
  int statusReads = 0;
  int jobReads = 0;
  AiRunResult runResult = const AiRunResult(processed: 2, succeeded: 1, failed: 1);
  int _next = 100;

  @override
  Future<AiStatus> status(int studyId) async {
    statusReads++;
    if (statusFailure != null) throw statusFailure!;
    return statusValue;
  }

  @override
  Future<AiBudget> setBudget(int studyId, double costCapUnits) async {
    if (budgetFailure != null) throw budgetFailure!;
    budgetChanges.add(costCapUnits);
    final spent = statusValue.budget.spentUnits;
    final budget = AiBudget(
      costCapUnits: costCapUnits,
      spentUnits: spent,
      remainingUnits: costCapUnits - spent,
    );
    statusValue = statusValue.copyWith(budget: budget);
    return budget;
  }

  @override
  Future<bool> setSendFreeText(int studyId, bool value) async {
    if (budgetFailure != null) throw budgetFailure!;
    freeTextChanges.add(value);
    statusValue = statusValue.copyWith(sendFreeText: value);
    return value;
  }

  @override
  Future<AiJob> createTextJob(int studyId, TextJobRequest request) async {
    if (textJobFailure != null) throw textJobFailure!;
    textRequests.add(request);
    final n = _next++;
    final job = AiJob(
      id: '$n',
      kind: AiJobKind.text,
      status: AiJobStatus.queued,
      provider: statusValue.textProvider.name,
      contentId: '${n + 1000}',
      assignmentId: request.assignmentId,
      costEstimateUnits: 0.05,
      createdAt: '2026-09-29T11:00:00',
    );
    jobList = [job, ...jobList];
    return job;
  }

  @override
  Future<List<AiJob>> createVideoJobs(
    int studyId,
    VideoJobRequest request,
  ) async {
    if (videoJobFailure != null) throw videoJobFailure!;
    videoRequests.add(request);
    final created = [
      for (final seg in request.segmentIds)
        AiJob(
          id: '${_next++}',
          kind: AiJobKind.video,
          status: AiJobStatus.queued,
          provider: statusValue.videoProvider.name,
          contentId: request.contentId,
          segmentId: seg,
          costEstimateUnits: 0.4,
          createdAt: '2026-09-29T11:05:00',
        ),
    ];
    jobList = [...created.reversed, ...jobList];
    return created;
  }

  @override
  Future<List<AiJob>> jobs(
    int studyId, {
    String? status,
    String? contentId,
  }) async {
    jobReads++;
    return [
      for (final j in jobList)
        if ((status == null || j.status == status) &&
            (contentId == null || j.contentId == contentId))
          j,
    ];
  }

  AiJob _replace(String id, AiJob Function(AiJob) change) {
    late AiJob next;
    jobList = [
      for (final j in jobList)
        if (j.id == id) next = change(j) else j,
    ];
    return next;
  }

  AiJob _copy(AiJob j, {String? status, String? error, int? attempts}) => AiJob(
        id: j.id,
        kind: j.kind,
        status: status ?? j.status,
        provider: j.provider,
        contentId: j.contentId,
        assignmentId: j.assignmentId,
        segmentId: j.segmentId,
        attempts: attempts ?? j.attempts,
        maxAttempts: j.maxAttempts,
        costEstimateUnits: j.costEstimateUnits,
        costActualUnits: j.costActualUnits,
        error: error ?? (status == null ? j.error : null),
        createdAt: j.createdAt,
      );

  @override
  Future<AiJob> cancel(int studyId, String jobId) async {
    if (actionFailure != null) throw actionFailure!;
    cancelled.add(jobId);
    return _replace(jobId, (j) => _copy(j, status: AiJobStatus.cancelled));
  }

  @override
  Future<AiJob> retry(int studyId, String jobId) async {
    if (actionFailure != null) throw actionFailure!;
    retried.add(jobId);
    return _replace(jobId, (j) => _copy(j, status: AiJobStatus.queued));
  }

  @override
  Future<AiRunResult> run(int studyId, {int maxJobs = 5}) async {
    if (actionFailure != null) throw actionFailure!;
    runs.add(maxJobs);
    jobList = [
      for (final j in jobList)
        j.status == AiJobStatus.queued
            ? _copy(j, status: AiJobStatus.succeeded)
            : j,
    ];
    return runResult;
  }
}


// ------------------------------------------------------------------ step 6

/// The step 6 endpoints, answering from what a test sets and recording what
/// the screens asked.
class FakePilotRepository implements PilotRepository {
  FakePilotRepository({this.settings});

  /// Supplies the settings history (a threshold save adds a version there).
  final FakeMeasurementSettingsRepository? settings;

  // ------------------------------------------------------- settings history
  List<SettingsVersion>? historyOverride;
  ApiException? historyFailure;
  int historyReads = 0;

  // ------------------------------------------------------ threshold review
  ThresholdReview reviewResult = const ThresholdReview();
  ApiException? reviewFailure;
  final List<({Map<String, dynamic> changes, bool includeSynthetic})> reviews = [];

  // ---------------------------------------------------------- observations
  final Map<String, List<Observation>> observationsBySession = {};
  ApiException? observationsFailure;
  ApiException? addObservationFailure;
  final List<({String sessionId, ObservationRequest request})> addedObservations = [];
  int _observationId = 100;

  // ---------------------------------------------------------- live monitor
  List<ActiveSession> active = [];
  ApiException? activeFailure;
  int activeReads = 0;

  /// What the next polls answer; the last one repeats.
  List<LiveStatus> liveQueue = [];
  ApiException? liveFailure;
  final List<({String sessionId, bool first})> liveCalls = [];

  // --------------------------------------------------------------- debrief
  DebriefForm form = const DebriefForm();
  ApiException? debriefLoadFailure;
  ApiException? debriefSaveFailure;
  final List<({List<DebriefQuestion>? questions, bool? enabled})> debriefSaves = [];

  // ------------------------------------------------- research eye tracker
  final Map<String, List<ReferenceRecording>> recordingsBySession = {};
  ReferenceComparison comparisonResult = const ReferenceComparison();
  ApiException? importFailure;
  ApiException? referencesFailure;
  ApiException? compareFailure;
  final List<({
    String sessionId,
    String filename,
    int size,
    ReferenceImportRequest request,
  })> imports = [];
  final List<({String sessionId, String recordingId, int toleranceMs})> compares = [];

  // ---------------------------------------------------------------- report
  PilotReport reportResult = const PilotReport();
  ApiException? reportFailure;
  final List<bool> reportRequests = [];
  Uint8List csvBytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x73, 0x0A]);
  final List<bool> csvRequests = [];
  ApiException? csvFailure;

  @override
  Future<List<SettingsVersion>> settingsHistory(int studyId) async {
    historyReads++;
    if (historyFailure != null) throw historyFailure!;
    return historyOverride ??
        settings?.history ??
        [const SettingsVersion(version: 1, rationale: 'Defaults; no change recorded yet')];
  }

  @override
  Future<ThresholdReview> thresholdReview(
    int studyId, {
    Map<String, dynamic> changes = const {},
    bool includeSynthetic = false,
  }) async {
    if (reviewFailure != null) throw reviewFailure!;
    reviews.add((changes: Map.of(changes), includeSynthetic: includeSynthetic));
    return reviewResult;
  }

  @override
  Future<List<Observation>> observations(int studyId, String sessionId) async {
    if (observationsFailure != null) throw observationsFailure!;
    return List.of(observationsBySession[sessionId] ?? const []);
  }

  @override
  Future<Observation> addObservation(
    int studyId,
    String sessionId,
    ObservationRequest request,
  ) async {
    if (addObservationFailure != null) throw addObservationFailure!;
    addedObservations.add((sessionId: sessionId, request: request));
    final created = Observation(
      id: '${_observationId++}',
      sessionId: sessionId,
      authorId: 7,
      category: request.category,
      severity: request.severity,
      text: request.text,
      tMs: request.tMs,
      createdAt: '2026-09-30T12:30:00',
    );
    observationsBySession.update(
      sessionId,
      (list) => [...list, created],
      ifAbsent: () => [created],
    );
    return created;
  }

  @override
  Future<List<ActiveSession>> activeSessions(int studyId) async {
    activeReads++;
    if (activeFailure != null) throw activeFailure!;
    return List.of(active);
  }

  @override
  Future<LiveStatus> live(int studyId, String sessionId, {bool first = false}) async {
    liveCalls.add((sessionId: sessionId, first: first));
    if (liveFailure != null) throw liveFailure!;
    if (liveQueue.isEmpty) return LiveStatus(sessionId: sessionId);
    final index = (liveCalls.length - 1).clamp(0, liveQueue.length - 1);
    return liveQueue[index];
  }

  @override
  Future<DebriefForm> debriefForm(int studyId) async {
    if (debriefLoadFailure != null) throw debriefLoadFailure!;
    return form;
  }

  @override
  Future<DebriefForm> saveDebriefForm(
    int studyId, {
    List<DebriefQuestion>? questions,
    bool? enabled,
  }) async {
    if (debriefSaveFailure != null) throw debriefSaveFailure!;
    debriefSaves.add((questions: questions, enabled: enabled));
    // What the server does: changed questions make the next version.
    final changed = questions != null &&
        (form.version == 0 ||
            questions.map((q) => q.toJson().toString()).join('|') !=
                form.questions.map((q) => q.toJson().toString()).join('|'));
    form = DebriefForm(
      version: changed ? form.version + 1 : form.version,
      enabled: enabled ?? form.enabled,
      questions: changed ? questions : form.questions,
      saved: true,
    );
    return form;
  }

  @override
  Future<ReferenceRecording> importReference(
    int studyId,
    String sessionId, {
    required Uint8List bytes,
    required String filename,
    required ReferenceImportRequest request,
  }) async {
    if (importFailure != null) throw importFailure!;
    imports.add((
      sessionId: sessionId,
      filename: filename,
      size: bytes.length,
      request: request,
    ));
    final recording = ReferenceRecording(
      id: '${900 + imports.length}',
      sessionId: sessionId,
      source: request.source,
      settings: {'alignment': request.autoAlignWindowMs > 0 ? 'estimated_from_data' : 'given_offset'},
      sampleCount: 1200,
      validCount: 1100,
      uploadedBy: 7,
      createdAt: '2026-09-30T13:00:00',
    );
    recordingsBySession.update(
      sessionId,
      (list) => [...list, recording],
      ifAbsent: () => [recording],
    );
    return recording;
  }

  @override
  Future<List<ReferenceRecording>> references(int studyId, String sessionId) async {
    if (referencesFailure != null) throw referencesFailure!;
    return List.of(recordingsBySession[sessionId] ?? const []);
  }

  @override
  Future<ReferenceComparison> compare(
    int studyId,
    String sessionId,
    String recordingId, {
    int toleranceMs = 40,
  }) async {
    if (compareFailure != null) throw compareFailure!;
    compares.add((sessionId: sessionId, recordingId: recordingId, toleranceMs: toleranceMs));
    return comparisonResult;
  }

  @override
  Future<PilotReport> report(int studyId, {bool includeSynthetic = false}) async {
    reportRequests.add(includeSynthetic);
    if (reportFailure != null) throw reportFailure!;
    return reportResult;
  }

  @override
  Future<Uint8List> reportCsv(int studyId, {bool includeSynthetic = false}) async {
    csvRequests.add(includeSynthetic);
    if (csvFailure != null) throw csvFailure!;
    return csvBytes;
  }
}

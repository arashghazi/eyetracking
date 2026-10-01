/// Practice protocol wire models (build step 3): the versioned definition a
/// session runs, and the list rows the Research Admin shows.
library;

import 'live.dart';

double _d(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;
int _i(Object? v, int fallback) => (v as num?)?.toInt() ?? fallback;
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;
List<String> _strings(Object? v) =>
    [for (final e in (v as List<dynamic>? ?? const [])) e.toString()];

/// The practice paths.
enum ProtocolPath {
  gradualFace('gradual_face', 'Gradual face practice'),
  interestConversation('interest_conversation', 'Interest conversation'),
  liveConversation('live_conversation', 'Live conversation with an avatar');

  const ProtocolPath(this.wire, this.label);
  final String wire;
  final String label;

  static ProtocolPath? maybeFromWire(String? value) {
    for (final p in values) {
      if (p.wire == value) return p;
    }
    return null;
  }
}

/// Where the number appears, in order of increasing closeness to the eyes.
enum NumberZone {
  outside('outside', 'Outside the face'),
  faceEdge('face_edge', 'Face edge'),
  nearEyes('near_eyes', 'Near the eyes'),
  eyeRegion('eye_region', 'Eye region');

  const NumberZone(this.wire, this.label);
  final String wire;
  final String label;

  static NumberZone fromWire(String? value) => values.firstWhere(
        (z) => z.wire == value,
        orElse: () => NumberZone.outside,
      );
}

/// How a stage collects the answer. `profile` means "use what the participant
/// chose in their profile".
enum StageResponseMode {
  number('number', 'Number entry'),
  fourChoice('four_choice', 'Four choices'),
  symbol('symbol', 'Symbols'),
  profile('profile', "Participant's profile");

  const StageResponseMode(this.wire, this.label);
  final String wire;
  final String label;

  static StageResponseMode fromWire(String? value) => values.firstWhere(
        (m) => m.wire == value,
        orElse: () => StageResponseMode.profile,
      );
}

/// The default five-point comfort scale.
const List<String> kDefaultComfortLabels = [
  'Very uncomfortable',
  'Uncomfortable',
  'Neutral',
  'Comfortable',
  'Very comfortable',
];

class ComfortConfig {
  const ComfortConfig({
    this.scaleMax = 5,
    this.labels = kDefaultComfortLabels,
    this.minOk = 3,
    this.askEveryStage = true,
  });

  final int scaleMax;

  /// One label per value 1..[scaleMax].
  final List<String> labels;

  /// Lowest value that counts as comfortable.
  final int minOk;
  final bool askEveryStage;

  factory ComfortConfig.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const ComfortConfig();
    final labels = _strings(value['labels']);
    final max = _i(value['scale_max'], labels.isEmpty ? 5 : labels.length);
    return ComfortConfig(
      scaleMax: max,
      labels: labels.isEmpty ? kDefaultComfortLabels : labels,
      minOk: _i(value['min_ok'], 3),
      askEveryStage: _b(value['ask_every_stage'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'scale_max': scaleMax,
        'labels': labels,
        'min_ok': minOk,
        'ask_every_stage': askEveryStage,
      };

  ComfortConfig copyWith({
    int? scaleMax,
    List<String>? labels,
    int? minOk,
    bool? askEveryStage,
  }) =>
      ComfortConfig(
        scaleMax: scaleMax ?? this.scaleMax,
        labels: labels ?? this.labels,
        minOk: minOk ?? this.minOk,
        askEveryStage: askEveryStage ?? this.askEveryStage,
      );

  /// Label of scale value [value] (1-based), or the number when unlabelled.
  String labelFor(int value) =>
      value >= 1 && value <= labels.length ? labels[value - 1] : '$value';
}

class ProgressionRules {
  const ProgressionRules({
    this.holdOnInvalidShareAbove = 0.3,
    this.easierOnComfortBelowMin = true,
    this.stopOnTwoLowComfort = true,
  });

  final double holdOnInvalidShareAbove;
  final bool easierOnComfortBelowMin;
  final bool stopOnTwoLowComfort;

  factory ProgressionRules.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const ProgressionRules();
    return ProgressionRules(
      holdOnInvalidShareAbove: _d(value['hold_on_invalid_share_above'], 0.3),
      easierOnComfortBelowMin: _b(value['easier_on_comfort_below_min'], true),
      stopOnTwoLowComfort: _b(value['stop_on_two_low_comfort'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'hold_on_invalid_share_above': holdOnInvalidShareAbove,
        'easier_on_comfort_below_min': easierOnComfortBelowMin,
        'stop_on_two_low_comfort': stopOnTwoLowComfort,
      };

  ProgressionRules copyWith({
    double? holdOnInvalidShareAbove,
    bool? easierOnComfortBelowMin,
    bool? stopOnTwoLowComfort,
  }) =>
      ProgressionRules(
        holdOnInvalidShareAbove:
            holdOnInvalidShareAbove ?? this.holdOnInvalidShareAbove,
        easierOnComfortBelowMin:
            easierOnComfortBelowMin ?? this.easierOnComfortBelowMin,
        stopOnTwoLowComfort: stopOnTwoLowComfort ?? this.stopOnTwoLowComfort,
      );
}

/// One stage of the gradual face path.
class GradualStage {
  const GradualStage({
    this.faceLevel = 0,
    this.numberZone = NumberZone.outside,
    this.trials = 6,
    this.minCorrect = 0.8,
    this.responseMode = StageResponseMode.profile,
    this.trialSeconds = 8,
  });

  /// 0 square, 1 face-like shape, 2 low-detail face, 3 approved real face.
  final int faceLevel;
  final NumberZone numberZone;
  final int trials;
  final double minCorrect;
  final StageResponseMode responseMode;
  final double trialSeconds;

  factory GradualStage.fromJson(Map<String, dynamic> json) => GradualStage(
        faceLevel: _i(json['face_level'], 0),
        numberZone: NumberZone.fromWire(json['number_zone'] as String?),
        trials: _i(json['trials'], 6),
        minCorrect: _d(json['min_correct'], 0.8),
        responseMode:
            StageResponseMode.fromWire(json['response_mode'] as String?),
        trialSeconds: _d(json['trial_seconds'], 8),
      );

  Map<String, dynamic> toJson() => {
        'face_level': faceLevel,
        'number_zone': numberZone.wire,
        'trials': trials,
        'min_correct': minCorrect,
        'response_mode': responseMode.wire,
        'trial_seconds': trialSeconds == trialSeconds.roundToDouble()
            ? trialSeconds.round()
            : trialSeconds,
      };

  GradualStage copyWith({
    int? faceLevel,
    NumberZone? numberZone,
    int? trials,
    double? minCorrect,
    StageResponseMode? responseMode,
    double? trialSeconds,
  }) =>
      GradualStage(
        faceLevel: faceLevel ?? this.faceLevel,
        numberZone: numberZone ?? this.numberZone,
        trials: trials ?? this.trials,
        minCorrect: minCorrect ?? this.minCorrect,
        responseMode: responseMode ?? this.responseMode,
        trialSeconds: trialSeconds ?? this.trialSeconds,
      );
}

class GradualConfig {
  const GradualConfig({
    this.stages = const [GradualStage()],
    this.finalZoneLimit = NumberZone.nearEyes,
    this.allowSimultaneousChange = false,
    this.realFaceMediaUrl,
  });

  final List<GradualStage> stages;
  final NumberZone finalZoneLimit;
  final bool allowSimultaneousChange;

  /// Approved real face image for face level 3; null uses the vector face.
  final String? realFaceMediaUrl;

  factory GradualConfig.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const GradualConfig(stages: []);
    final url = value['real_face_media_url'];
    return GradualConfig(
      stages: [
        for (final s in (value['stages'] as List<dynamic>? ?? const []))
          GradualStage.fromJson(s as Map<String, dynamic>),
      ],
      finalZoneLimit:
          NumberZone.fromWire(value['final_zone_limit'] as String? ?? 'near_eyes'),
      allowSimultaneousChange: _b(value['allow_simultaneous_change'], false),
      realFaceMediaUrl: url is String && url.trim().isNotEmpty ? url : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'stages': [for (final s in stages) s.toJson()],
        'final_zone_limit': finalZoneLimit.wire,
        'allow_simultaneous_change': allowSimultaneousChange,
        'real_face_media_url': realFaceMediaUrl,
      };
}

class InterestConfig {
  const InterestConfig({this.interactionPoints = 2});

  final int interactionPoints;

  factory InterestConfig.fromJson(Object? value) => value is Map<String, dynamic>
      ? InterestConfig(interactionPoints: _i(value['interaction_points'], 2))
      : const InterestConfig();

  Map<String, dynamic> toJson() => {'interaction_points': interactionPoints};
}

/// The JSON a published protocol version freezes.
class ProtocolDefinition {
  const ProtocolDefinition({
    required this.path,
    this.baselineSeconds = 30,
    this.postSeconds = 30,
    this.comfort = const ComfortConfig(),
    this.progression = const ProgressionRules(),
    this.gradual,
    this.interest,
    this.live,
  });

  final ProtocolPath path;
  final double baselineSeconds;
  final double postSeconds;
  final ComfortConfig comfort;
  final ProgressionRules progression;

  /// Present for [ProtocolPath.gradualFace].
  final GradualConfig? gradual;

  /// Present for [ProtocolPath.interestConversation].
  final InterestConfig? interest;

  /// Present for [ProtocolPath.liveConversation].
  final LiveProtocolConfig? live;

  /// A sensible starting point for a new draft of [path].
  factory ProtocolDefinition.starter(ProtocolPath path) => ProtocolDefinition(
        path: path,
        gradual: path == ProtocolPath.gradualFace
            ? const GradualConfig(stages: [
                GradualStage(),
                GradualStage(numberZone: NumberZone.faceEdge),
              ])
            : null,
        interest:
            path == ProtocolPath.interestConversation ? const InterestConfig() : null,
        live: path == ProtocolPath.liveConversation
            ? const LiveProtocolConfig()
            : null,
      );

  static ProtocolDefinition? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final path = ProtocolPath.maybeFromWire(value['path'] as String?);
    if (path == null) return null;
    return ProtocolDefinition(
      path: path,
      baselineSeconds: _d(value['baseline_seconds'], 30),
      postSeconds: _d(value['post_seconds'], 30),
      comfort: ComfortConfig.fromJson(value['comfort']),
      progression: ProgressionRules.fromJson(value['progression']),
      gradual: value['gradual'] == null
          ? null
          : GradualConfig.fromJson(value['gradual']),
      interest: value['interest'] == null
          ? null
          : InterestConfig.fromJson(value['interest']),
      live: value['live'] == null
          ? null
          : LiveProtocolConfig.fromJson(value['live']),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path.wire,
        'baseline_seconds': baselineSeconds == baselineSeconds.roundToDouble()
            ? baselineSeconds.round()
            : baselineSeconds,
        'post_seconds': postSeconds == postSeconds.roundToDouble()
            ? postSeconds.round()
            : postSeconds,
        'comfort': comfort.toJson(),
        'progression': progression.toJson(),
        if (path == ProtocolPath.gradualFace && gradual != null)
          'gradual': gradual!.toJson(),
        if (path == ProtocolPath.interestConversation && interest != null)
          'interest': interest!.toJson(),
        if (path == ProtocolPath.liveConversation && live != null)
          'live': live!.toJson(),
      };
}

/// Identity of a protocol version. The participant's session summary also
/// carries the frozen [definition].
class ProtocolRef {
  const ProtocolRef({
    required this.id,
    required this.name,
    this.version = 0,
    this.path,
    this.definition,
  });

  final String id;
  final String name;
  final int version;
  final ProtocolPath? path;
  final ProtocolDefinition? definition;

  static ProtocolRef? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final definition = ProtocolDefinition.maybeFromJson(value['definition']);
    return ProtocolRef(
      id: value['id']?.toString() ?? '',
      name: value['name']?.toString() ?? '',
      version: _i(value['version'], 0),
      path: ProtocolPath.maybeFromWire(value['path'] as String?) ??
          definition?.path,
      definition: definition,
    );
  }
}

abstract final class ProtocolStatus {
  static const draft = 'draft';
  static const published = 'published';
}

/// One row of the protocol list.
class ProtocolSummary {
  const ProtocolSummary({
    required this.id,
    required this.name,
    this.version = 0,
    this.status = ProtocolStatus.draft,
    this.path,
    this.createdAt,
    this.publishedAt,
  });

  final String id;
  final String name;
  final int version;
  final String status;
  final ProtocolPath? path;
  final String? createdAt;
  final String? publishedAt;

  bool get isDraft => status == ProtocolStatus.draft;
  bool get isPublished => status == ProtocolStatus.published;

  factory ProtocolSummary.fromJson(Map<String, dynamic> json) =>
      ProtocolSummary(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        version: _i(json['version'], 0),
        status: json['status']?.toString() ?? ProtocolStatus.draft,
        path: ProtocolPath.maybeFromWire(json['path'] as String?),
        createdAt: json['created_at']?.toString(),
        publishedAt: json['published_at']?.toString(),
      );
}

/// A protocol with its definition, as the editor loads it.
class ProtocolDetail {
  const ProtocolDetail({required this.summary, required this.definition});

  final ProtocolSummary summary;
  final ProtocolDefinition definition;

  factory ProtocolDetail.fromJson(Map<String, dynamic> json) {
    final summary = ProtocolSummary.fromJson(json);
    final definition = ProtocolDefinition.maybeFromJson(json['definition']) ??
        ProtocolDefinition.starter(summary.path ?? ProtocolPath.gradualFace);
    return ProtocolDetail(summary: summary, definition: definition);
  }
}

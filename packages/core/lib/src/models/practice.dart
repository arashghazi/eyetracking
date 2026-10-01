/// Wire models for what happens during practice: trials, stage decisions and
/// answers, plus the outcome blocks of the session summary.
library;

import 'live.dart';

double? _d(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// One number (or symbol) the participant was shown and what they answered.
class TrialRecord {
  const TrialRecord({
    required this.stageIndex,
    required this.trialIndex,
    required this.tMs,
    required this.numberShown,
    required this.zone,
    required this.x,
    required this.y,
    required this.faceLevel,
    this.response,
    this.responseMs,
  });

  final int stageIndex;
  final int trialIndex;
  final int tMs;

  /// The number shown, or the symbol name in symbol mode.
  final String numberShown;
  final String zone;

  /// Centre of the number in CSS pixels of the screen.
  final double x;
  final double y;
  final int faceLevel;

  /// Null when the time ran out without an answer.
  final String? response;
  final int? responseMs;

  Map<String, dynamic> toJson() => {
        'stage_index': stageIndex,
        'trial_index': trialIndex,
        't_ms': tMs,
        'number_shown': numberShown,
        'zone': zone,
        'position': {'x': x.roundToDouble(), 'y': y.roundToDouble()},
        'face_level': faceLevel,
        'response': response,
        'response_ms': responseMs,
      };
}

class TrialAck {
  const TrialAck({required this.stored, required this.correct});

  final int stored;
  final int correct;

  factory TrialAck.fromJson(Map<String, dynamic> json) =>
      TrialAck(stored: _i(json['stored']), correct: _i(json['correct']));
}

/// What to do after a stage.
enum StageDecisionKind {
  advance('advance'),
  hold('hold'),
  easier('easier'),
  stop('stop'),
  complete('complete');

  const StageDecisionKind(this.wire);
  final String wire;

  /// An unknown word never moves the participant forward.
  static StageDecisionKind fromWire(String? value) => values.firstWhere(
        (k) => k.wire == value,
        orElse: () => StageDecisionKind.hold,
      );
}

/// The server's answer to `POST .../stage-result`.
class StageDecision {
  const StageDecision({
    required this.kind,
    this.nextStageIndex,
    this.reason = '',
    this.correctRatio,
    this.invalidShare,
    this.trials = 0,
  });

  final StageDecisionKind kind;
  final int? nextStageIndex;
  final String reason;
  final double? correctRatio;
  final double? invalidShare;
  final int trials;

  factory StageDecision.fromJson(Map<String, dynamic> json) => StageDecision(
        kind: StageDecisionKind.fromWire(json['decision'] as String?),
        nextStageIndex: (json['next_stage_index'] as num?)?.toInt(),
        reason: json['reason']?.toString() ?? '',
        correctRatio: _d(json['correct_ratio']),
        invalidShare: _d(json['invalid_share']),
        trials: _i(json['trials']),
      );
}

abstract final class AnswerKind {
  static const interaction = 'interaction';
  static const comprehension = 'comprehension';
}

class AnswerRequest {
  const AnswerRequest({
    required this.segmentId,
    required this.questionId,
    required this.kind,
    required this.option,
    required this.tMs,
  });

  final String segmentId;
  final String questionId;
  final String kind;
  final String option;
  final int tMs;

  Map<String, dynamic> toJson() => {
        'segment_id': segmentId,
        'question_id': questionId,
        'kind': kind,
        'option': option,
        't_ms': tMs,
      };
}

/// `correct` is null for interaction answers; `nextSegmentId` is null when
/// the conversation ends.
class AnswerResult {
  const AnswerResult({this.correct, this.nextSegmentId});

  final bool? correct;
  final String? nextSegmentId;

  factory AnswerResult.fromJson(Map<String, dynamic> json) {
    final next = json['next_segment_id']?.toString();
    return AnswerResult(
      correct: json['correct'] as bool?,
      nextSegmentId: next == null || next.isEmpty ? null : next,
    );
  }
}

// ---------------------------------------------------------------- outcomes

class GazeOutcome {
  const GazeOutcome({
    this.baselineEyeShare,
    this.postEyeShare,
    this.evaluable = false,
    this.reason,
  });

  final double? baselineEyeShare;
  final double? postEyeShare;
  final bool evaluable;
  final String? reason;

  factory GazeOutcome.fromJson(Object? v) {
    if (v is! Map<String, dynamic>) return const GazeOutcome();
    return GazeOutcome(
      baselineEyeShare: _d(v['baseline_eye_share']),
      postEyeShare: _d(v['post_eye_share']),
      evaluable: v['evaluable'] == true,
      reason: v['reason']?.toString(),
    );
  }
}

class ComprehensionOutcome {
  const ComprehensionOutcome({this.answered = 0, this.correct = 0, this.share});

  final int answered;
  final int correct;
  final double? share;

  factory ComprehensionOutcome.fromJson(Object? v) {
    if (v is! Map<String, dynamic>) return const ComprehensionOutcome();
    return ComprehensionOutcome(
      answered: _i(v['answered']),
      correct: _i(v['correct']),
      share: _d(v['share']),
    );
  }
}

class NumberTaskOutcome {
  const NumberTaskOutcome({
    this.trials = 0,
    this.correct = 0,
    this.share,
    this.stagesCompleted = 0,
  });

  final int trials;
  final int correct;
  final double? share;
  final int stagesCompleted;

  factory NumberTaskOutcome.fromJson(Object? v) {
    if (v is! Map<String, dynamic>) return const NumberTaskOutcome();
    return NumberTaskOutcome(
      trials: _i(v['trials']),
      correct: _i(v['correct']),
      share: _d(v['share']),
      stagesCompleted: _i(v['stages_completed']),
    );
  }
}

class ComfortOutcome {
  const ComfortOutcome({
    this.answers = 0,
    this.min,
    this.mean,
    this.lowCount = 0,
    this.pauses = 0,
    this.endedEarly = false,
  });

  final int answers;
  final int? min;
  final double? mean;
  final int lowCount;
  final int pauses;
  final bool endedEarly;

  factory ComfortOutcome.fromJson(Object? v) {
    if (v is! Map<String, dynamic>) return const ComfortOutcome();
    return ComfortOutcome(
      answers: _i(v['answers']),
      min: (v['min'] as num?)?.toInt(),
      mean: _d(v['mean']),
      lowCount: _i(v['low_count']),
      pauses: _i(v['pauses']),
      endedEarly: v['ended_early'] == true,
    );
  }
}

/// True only when all three criteria hold; null when it cannot be judged.
class ImprovementOutcome {
  const ImprovementOutcome({
    this.eligible = false,
    this.result,
    this.eyeShareUp,
    this.comfortNotWorse,
    this.comprehensionMaintained,
    this.reason,
  });

  final bool eligible;
  final bool? result;
  final bool? eyeShareUp;
  final bool? comfortNotWorse;
  final bool? comprehensionMaintained;
  final String? reason;

  factory ImprovementOutcome.fromJson(Object? v) {
    if (v is! Map<String, dynamic>) return const ImprovementOutcome();
    final criteria = v['criteria'];
    final c = criteria is Map<String, dynamic> ? criteria : const {};
    return ImprovementOutcome(
      eligible: v['eligible'] == true,
      result: v['result'] as bool?,
      eyeShareUp: c['eye_share_up'] as bool?,
      comfortNotWorse: c['comfort_not_worse'] as bool?,
      comprehensionMaintained: c['comprehension_maintained'] as bool?,
      reason: v['reason']?.toString(),
    );
  }
}

/// The `outcomes` block of a session summary.
class SessionOutcomes {
  const SessionOutcomes({
    this.gaze = const GazeOutcome(),
    this.comprehension = const ComprehensionOutcome(),
    this.numberTask = const NumberTaskOutcome(),
    this.comfort = const ComfortOutcome(),
    this.improvement = const ImprovementOutcome(),
    this.conversation,
  });

  final GazeOutcome gaze;
  final ComprehensionOutcome comprehension;
  final NumberTaskOutcome numberTask;
  final ComfortOutcome comfort;
  final ImprovementOutcome improvement;

  /// Step 7: counts and the reply model's on-topic judgement of the live
  /// conversation; null on the other paths.
  final ConversationOutcome? conversation;

  static SessionOutcomes? maybeFromJson(Object? v) {
    if (v is! Map<String, dynamic>) return null;
    return SessionOutcomes(
      gaze: GazeOutcome.fromJson(v['gaze']),
      comprehension: ComprehensionOutcome.fromJson(v['comprehension']),
      numberTask: NumberTaskOutcome.fromJson(v['number_task']),
      comfort: ComfortOutcome.fromJson(v['comfort']),
      improvement: ImprovementOutcome.fromJson(v['improvement']),
      conversation: ConversationOutcome.maybeFromJson(v['conversation']),
    );
  }
}

/// Plain wording for the reason codes the server puts in the outcomes.
String outcomeReasonLabel(String? reason) {
  if (reason == null || reason.isEmpty) return '';
  return switch (reason) {
    'synthetic_estimator' => 'The development estimator makes no measurement claims.',
    'gaze_not_evaluable' => 'Eye-region attention could not be evaluated.',
    'baseline_or_post_missing' =>
      'There is no baseline or no post observation to compare.',
    'no_comfort_answers' => 'No comfort answers were given.',
    'no_content_responses' => 'No answers to the practice task were given.',
    'validation_not_passed' => 'The regional validation did not pass.',
    _ => () {
        final text = reason.replaceAll('_', ' ');
        final sentence = text[0].toUpperCase() + text.substring(1);
        return sentence.endsWith('.') ? sentence : '$sentence.';
      }(),
  };
}

/// One stage decision inside a session summary.
class StageRecord {
  const StageRecord({
    required this.stageIndex,
    required this.decision,
    this.reason = '',
    this.correctRatio,
    this.invalidShare,
    this.comfortValue,
    this.trials = 0,
  });

  final int stageIndex;
  final String decision;
  final String reason;
  final double? correctRatio;
  final double? invalidShare;
  final int? comfortValue;
  final int trials;

  factory StageRecord.fromJson(Map<String, dynamic> json) => StageRecord(
        stageIndex: _i(json['stage_index']),
        decision: json['decision']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        correctRatio: _d(json['correct_ratio']),
        invalidShare: _d(json['invalid_share']),
        comfortValue: (json['comfort_value'] as num?)?.toInt(),
        trials: _i(json['trials']),
      );
}

// --------------------------------------------- researcher-only detail rows

class TrialRow {
  const TrialRow({
    required this.stageIndex,
    required this.trialIndex,
    this.tMs = 0,
    this.numberShown = '',
    this.zone = '',
    this.faceLevel,
    this.response,
    this.responseMs,
    this.correct,
  });

  final int stageIndex;
  final int trialIndex;
  final int tMs;
  final String numberShown;
  final String zone;
  final int? faceLevel;
  final String? response;
  final int? responseMs;
  final bool? correct;

  factory TrialRow.fromJson(Map<String, dynamic> json) => TrialRow(
        stageIndex: _i(json['stage_index']),
        trialIndex: _i(json['trial_index']),
        tMs: _i(json['t_ms']),
        numberShown: json['number_shown']?.toString() ?? '',
        zone: json['zone']?.toString() ?? '',
        faceLevel: (json['face_level'] as num?)?.toInt(),
        response: json['response']?.toString(),
        responseMs: (json['response_ms'] as num?)?.toInt(),
        correct: json['correct'] as bool?,
      );
}

class AnswerRow {
  const AnswerRow({
    this.segmentId = '',
    this.questionId = '',
    this.kind = '',
    this.option = '',
    this.correct,
    this.tMs = 0,
    this.nextSegmentId,
  });

  final String segmentId;
  final String questionId;
  final String kind;
  final String option;
  final bool? correct;
  final int tMs;
  final String? nextSegmentId;

  factory AnswerRow.fromJson(Map<String, dynamic> json) => AnswerRow(
        segmentId: json['segment_id']?.toString() ?? '',
        questionId: json['question_id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        option: json['option']?.toString() ?? '',
        correct: json['correct'] as bool?,
        tMs: _i(json['t_ms']),
        nextSegmentId: json['next_segment_id']?.toString(),
      );
}

class ComfortAnswerRow {
  const ComfortAnswerRow({
    required this.value,
    this.tMs = 0,
    this.stageIndex,
    this.segment,
  });

  final int value;
  final int tMs;
  final int? stageIndex;
  final String? segment;

  factory ComfortAnswerRow.fromJson(Map<String, dynamic> json) {
    // Rows may be flat or carry the event payload.
    final payload = json['payload'];
    final p = payload is Map<String, dynamic> ? payload : json;
    return ComfortAnswerRow(
      value: _i(p['value']),
      tMs: _i(json['t_ms']),
      stageIndex: (p['stage_index'] as num?)?.toInt(),
      segment: p['segment']?.toString(),
    );
  }
}

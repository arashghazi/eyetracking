/// The debrief form the study shows after a session, and the participant's
/// answer to it. These models belong to this feature only (wire format of
/// `/me/sessions/{sid}/debrief`, see docs/api/step6-pilot.md). They carry a
/// `Participant` prefix because the shared package has its own admin-side
/// `DebriefForm` / `DebriefQuestion` for editing the form.
library;

/// Kinds of question the app can show.
enum ParticipantDebriefQuestionType {
  scale('scale'),
  yesNo('yes_no'),
  choice('choice'),
  text('text');

  const ParticipantDebriefQuestionType(this.wire);

  final String wire;

  /// Null for a type this app version does not know.
  static ParticipantDebriefQuestionType? fromWire(Object? value) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

/// Longest free-text answer the service accepts.
const int debriefTextMaxLength = 1000;

class ParticipantDebriefQuestion {
  const ParticipantDebriefQuestion({
    required this.key,
    required this.type,
    required this.prompt,
    this.required = false,
    this.scaleMax = 5,
    this.labels = const [],
    this.options = const [],
  });

  final String key;
  final ParticipantDebriefQuestionType type;
  final String prompt;
  final bool required;

  /// Scale only: the points are 1..[scaleMax].
  final int scaleMax;

  /// Scale only: one label per point (may be empty).
  final List<String> labels;

  /// Choice only.
  final List<String> options;

  /// The label of scale point [value], or null when there is none.
  String? labelFor(int value) =>
      value >= 1 && value <= labels.length && labels[value - 1].isNotEmpty
      ? labels[value - 1]
      : null;

  /// Whether [value] is a valid answer to this question: an int within the
  /// scale, a bool, one of the options, or a non-empty text within the limit.
  bool accepts(Object? value) => switch (type) {
    ParticipantDebriefQuestionType.scale =>
      value is int && value >= 1 && value <= scaleMax,
    ParticipantDebriefQuestionType.yesNo => value is bool,
    ParticipantDebriefQuestionType.choice =>
      value is String && options.contains(value),
    ParticipantDebriefQuestionType.text =>
      value is String &&
          value.trim().isNotEmpty &&
          value.length <= debriefTextMaxLength,
  };

  /// Null when the question cannot be shown (unknown type or no key).
  static ParticipantDebriefQuestion? tryParse(Object? json) {
    if (json is! Map) return null;
    final type = ParticipantDebriefQuestionType.fromWire(json['type']);
    final key = json['key'];
    if (type == null || key is! String || key.isEmpty) return null;
    final labels = [
      if (json['labels'] is List)
        for (final l in json['labels'] as List) '$l',
    ];
    final scaleMax =
        (json['scale_max'] as num?)?.toInt() ??
        (labels.isNotEmpty ? labels.length : 5);
    return ParticipantDebriefQuestion(
      key: key,
      type: type,
      prompt: json['prompt']?.toString() ?? '',
      required: json['required'] == true,
      scaleMax: scaleMax.clamp(2, 10),
      labels: labels,
      options: [
        if (json['options'] is List)
          for (final o in json['options'] as List) '$o',
      ],
    );
  }
}

class ParticipantDebriefForm {
  const ParticipantDebriefForm({
    required this.version,
    this.enabled = true,
    this.questions = const [],
  });

  final int version;
  final bool enabled;
  final List<ParticipantDebriefQuestion> questions;

  factory ParticipantDebriefForm.fromJson(Map<String, dynamic> json) =>
      ParticipantDebriefForm(
        version: (json['version'] as num?)?.toInt() ?? 0,
        enabled: json['enabled'] != false,
        questions: [
          if (json['questions'] is List)
            for (final q in json['questions'] as List)
              ?ParticipantDebriefQuestion.tryParse(q),
        ],
      );
}

/// What the participant sent (or the server stored): the form version, the
/// answers by question key and whether the questions were skipped.
///
/// Values are `int` (scale), `bool` (yes/no) and `String` (choice, text).
class DebriefAnswer {
  const DebriefAnswer({
    required this.formVersion,
    this.answers = const {},
    this.skipped = false,
    this.createdAt,
  });

  final int formVersion;
  final Map<String, Object> answers;
  final bool skipped;
  final String? createdAt;

  factory DebriefAnswer.fromJson(Map<String, dynamic> json) {
    final raw = json['answers'];
    return DebriefAnswer(
      formVersion: (json['form_version'] as num?)?.toInt() ?? 0,
      answers: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is bool || e.value is String)
              '${e.key}': e.value as Object
            else if (e.value is num)
              '${e.key}': (e.value as num).toInt(),
      },
      skipped: json['skipped'] == true,
      createdAt: json['created_at']?.toString(),
    );
  }

  /// The body of `POST /me/sessions/{sid}/debrief`.
  Map<String, dynamic> toJson() => {
    'form_version': formVersion,
    'answers': answers,
    'skipped': skipped,
  };
}

/// The answer of `GET /me/sessions/{sid}/debrief`.
class SessionDebrief {
  const SessionDebrief({
    required this.enabled,
    required this.sessionEnded,
    this.form,
    this.answer,
  });

  final bool enabled;
  final bool sessionEnded;
  final ParticipantDebriefForm? form;
  final DebriefAnswer? answer;

  factory SessionDebrief.fromJson(Map<String, dynamic> json) {
    final form = json['form'];
    final answer = json['answer'];
    return SessionDebrief(
      enabled: json['enabled'] == true,
      sessionEnded: json['session_ended'] == true,
      form: form is Map<String, dynamic>
          ? ParticipantDebriefForm.fromJson(form)
          : null,
      answer: answer is Map<String, dynamic>
          ? DebriefAnswer.fromJson(answer)
          : null,
    );
  }

  /// The questions are offered only after the session has ended, while the
  /// study has the debrief on, the form has something to ask and the
  /// participant has not answered (or skipped) yet.
  bool get shouldAsk =>
      enabled &&
      sessionEnded &&
      answer == null &&
      form != null &&
      form!.enabled &&
      form!.questions.isNotEmpty;
}

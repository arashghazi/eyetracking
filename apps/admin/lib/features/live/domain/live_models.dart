/// Staff-side wire models of the live avatar (build step 7), for the Research
/// Admin: the provider status, a session's conversation and the conversation
/// parts of the live monitor and the pilot report. Contract:
/// docs/api/step7-live-avatar.md.
///
/// The participant-side shapes (conversation, turns, outcome, protocol
/// settings) come from `eyetracking_core`. Parsing is tolerant: nulls where
/// the contract allows them, defaults elsewhere.
library;

import 'package:eyetracking_core/eyetracking_core.dart';

int _i(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
int? _iOrNull(Object? v) => (v as num?)?.toInt();
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dOrNull(Object? v) => (v as num?)?.toDouble();
String _s(Object? v) => v?.toString() ?? '';
String? _sOrNull(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : const {};

// ---------------------------------------------------------------- status

/// One provider of `GET /studies/{id}/live/status`. Reply providers carry a
/// model and an effort, speech providers a model and the address of a local
/// server, avatar providers say whether they stream. Keys never arrive.
class LiveProviderInfo {
  const LiveProviderInfo({
    this.name = '',
    this.model,
    this.effort,
    this.baseUrl,
    this.configured = false,
    this.synthetic = false,
    this.streaming,
  });

  final String name;
  final String? model;
  final String? effort;
  final String? baseUrl;
  final bool configured;

  /// A development stand-in that produces sample content.
  final bool synthetic;

  /// Avatar providers only: false means no streaming avatar is connected.
  final bool? streaming;

  factory LiveProviderInfo.fromJson(Object? value) {
    final json = _map(value);
    return LiveProviderInfo(
      name: _s(json['name']),
      model: _sOrNull(json['model']),
      effort: _sOrNull(json['effort']),
      baseUrl: _sOrNull(json['base_url']),
      configured: json['configured'] == true,
      synthetic: json['synthetic'] == true,
      streaming: json['streaming'] is bool ? json['streaming'] as bool : null,
    );
  }
}

/// `GET /studies/{id}/live/status`.
class LiveAvatarStatus {
  const LiveAvatarStatus({
    this.reply = const LiveProviderInfo(),
    this.speech = const LiveProviderInfo(),
    this.avatar = const LiveProviderInfo(),
    this.perTurnUnits = 0,
    this.avatarPerMinuteUnits = 0,
    this.budget = const AiBudget(),
    this.sendFreeText = false,
    this.openConversations = 0,
    this.note = '',
  });

  final LiveProviderInfo reply;
  final LiveProviderInfo speech;
  final LiveProviderInfo avatar;

  /// Estimated cost of one reply, in the study's USD-estimate units.
  final double perTurnUnits;

  /// Estimated cost of a minute of streaming avatar (0 for the development
  /// avatar).
  final double avatarPerMinuteUnits;

  /// The study's shared AI budget; live replies count against it.
  final AiBudget budget;
  final bool sendFreeText;
  final int openConversations;
  final String note;

  factory LiveAvatarStatus.fromJson(Map<String, dynamic> json) {
    final estimates = _map(json['estimates']);
    return LiveAvatarStatus(
      reply: LiveProviderInfo.fromJson(json['reply_provider']),
      speech: LiveProviderInfo.fromJson(json['speech_provider']),
      avatar: LiveProviderInfo.fromJson(json['avatar_provider']),
      perTurnUnits: _d(estimates['per_turn_units']),
      avatarPerMinuteUnits: _d(estimates['avatar_per_minute_units']),
      budget: AiBudget.fromJson(json['budget']),
      sendFreeText: _map(json['budget'])['send_free_text'] == true,
      openConversations: _i(json['open_conversations']),
      note: _s(json['note']),
    );
  }
}

// ----------------------------------------------------------- conversation

/// `GET /studies/{id}/sessions/{sid}/conversation`: the conversation of one
/// session as staff see it. Turn text is present only when the protocol kept
/// transcripts and the participant agreed ([LiveConversation.transcriptAllowed]).
class StaffConversation {
  const StaffConversation({
    required this.conversation,
    this.turns = const [],
    this.outcome = const ConversationOutcome(),
    this.costUnits = 0,
    this.note = '',
  });

  final LiveConversation conversation;
  final List<LiveTurn> turns;
  final ConversationOutcome outcome;

  /// What the replies of this conversation cost, in USD-estimate units.
  final double costUnits;
  final String note;

  bool get textKept => conversation.transcriptAllowed;

  factory StaffConversation.fromJson(Map<String, dynamic> json) =>
      StaffConversation(
        conversation: LiveConversation.maybeFromJson(json['conversation']) ??
            const LiveConversation(id: ''),
        turns: LiveTurn.listFromJson(json['turns']),
        outcome: ConversationOutcome.maybeFromJson(json['outcome']) ??
            const ConversationOutcome(),
        costUnits: _d(json['cost_units']),
        note: _s(json['note']),
      );
}

// ------------------------------------------------------------ live monitor

/// The last turn of a conversation as the live monitor shows it.
class MonitorLastTurn {
  const MonitorLastTurn({this.role = '', this.flags = const [], this.tMs});

  final String role;
  final List<String> flags;
  final int? tMs;

  factory MonitorLastTurn.fromJson(Map<String, dynamic> json) => MonitorLastTurn(
        role: _s(json['role']),
        flags: [for (final f in (json['flags'] as List<dynamic>? ?? const [])) '$f'],
        tMs: _iOrNull(json['t_ms']),
      );
}

/// The `conversation` block of the live monitor
/// (`GET /studies/{id}/sessions/{sid}/live`), null for a session without one.
class ConversationMonitor {
  const ConversationMonitor({
    this.status = ConversationStatus.open,
    this.inputMode,
    this.turnsUsed = 0,
    this.distress = 0,
    this.redirects = 0,
    this.lastTurn,
    this.endReason,
  });

  final String status;
  final LiveInputMode? inputMode;
  final int turnsUsed;

  /// Participant turns flagged as distress.
  final int distress;

  /// Replies that sent the conversation back to the topic.
  final int redirects;
  final MonitorLastTurn? lastTurn;
  final String? endReason;

  bool get isOpen => status == ConversationStatus.open;

  static ConversationMonitor? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final last = value['last_turn'];
    return ConversationMonitor(
      status: _s(value['status']).isEmpty
          ? ConversationStatus.open
          : _s(value['status']),
      inputMode: LiveInputMode.maybeFromWire(value['input_mode']),
      turnsUsed: _i(value['turns_used']),
      distress: _i(value['distress']),
      redirects: _i(value['redirects']),
      lastTurn:
          last is Map<String, dynamic> ? MonitorLastTurn.fromJson(last) : null,
      endReason: _sOrNull(value['end_reason']),
    );
  }
}

// ------------------------------------------------------------ pilot report

/// The four conversation columns of a pilot report row (null for a session
/// without a live conversation).
class ConversationReportColumns {
  const ConversationReportColumns({
    this.turns,
    this.onTopicShare,
    this.distress,
    this.endReason,
  });

  /// Participant turns.
  final int? turns;
  final double? onTopicShare;
  final int? distress;
  final String? endReason;

  factory ConversationReportColumns.fromRow(Map<String, dynamic> row) =>
      ConversationReportColumns(
        turns: _iOrNull(row['conversation_turns']),
        onTopicShare: _dOrNull(row['conversation_on_topic_share']),
        distress: _iOrNull(row['conversation_distress']),
        endReason: _sOrNull(row['conversation_end_reason']),
      );

  bool get isEmpty =>
      turns == null &&
      onTopicShare == null &&
      distress == null &&
      endReason == null;
}

// ------------------------------------------------------------------ labels

/// Staff wording for the input mode of a conversation.
String conversationInputModeLabel(LiveInputMode? mode) => switch (mode) {
      null => '-',
      LiveInputMode.typed => 'Typed',
      LiveInputMode.speech => 'Speech',
    };

/// Staff wording for `end_reason` of a conversation ("-" when open).
String conversationEndReasonLabel(String? reason) => switch (reason) {
      null || '' => '-',
      LiveEndReason.participant => 'Participant asked to stop',
      LiveEndReason.participantEnded => 'Participant pressed End',
      LiveEndReason.turnLimit => 'Turn limit reached',
      LiveEndReason.timeLimit => 'Time limit reached',
      LiveEndReason.budget => 'Budget used up',
      LiveEndReason.sessionEnded => 'Session ended',
      _ => _sentence(reason),
    };

String _sentence(String raw) {
  final text = raw.replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}

/// Short wording for a turn flag; an unknown flag reads as its own words.
String conversationFlagLabel(String flag) => switch (flag) {
      'typed' => 'Typed',
      'speech' => 'Speech',
      'sample_speech' => 'Sample speech',
      'participant_truncated' => 'Cut to the limit',
      'participant_on_topic' => 'On topic',
      'participant_off_topic' => 'Off topic',
      'distress' => 'Distress',
      'scripted_line' => 'Scripted line',
      'opening' => 'Opening',
      'closing' => 'Closing',
      'redirect_line' => 'Redirect line',
      'fallback_line' => 'Fallback line',
      'reply_shortened' => 'Reply shortened',
      'participant_wants_to_stop' => 'Wants to stop',
      'refusal' => 'Refusal',
      'provider_error' => 'Provider error',
      'no_reply' => 'No reply',
      'contact_or_link' => 'Contact or link removed',
      'clinical_or_research_words' => 'Clinical or research words',
      'empty_reply' => 'Empty reply',
      'turn_limit' => 'Turn limit',
      'time_limit' => 'Time limit',
      'budget' => 'Budget',
      _ => _sentence(flag),
    };

/// Flags that deserve a second look: distress and a reply the server had to
/// replace or refuse.
bool conversationFlagNeedsAttention(String flag) => const {
      'distress',
      'participant_wants_to_stop',
      'refusal',
      'provider_error',
      'contact_or_link',
      'clinical_or_research_words',
    }.contains(flag);

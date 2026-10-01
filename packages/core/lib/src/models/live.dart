/// Live interactive avatar (build step 7): the participant's conversation, its
/// turns and limits, the avatar configuration, the answers of the `live`
/// endpoints, the protocol settings of the `live_conversation` path and the
/// conversation outcome of a session summary. Contract:
/// docs/api/step7-live-avatar.md.
///
/// Parsing is tolerant: nulls where the contract allows them, defaults
/// elsewhere.
library;

import 'content.dart' show NormalizedFaceLayout;

int _i(Object? v, int fallback) => (v as num?)?.toInt() ?? fallback;
double? _dOrNull(Object? v) => (v as num?)?.toDouble();
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;
String? _sOrNull(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

String _s(Object? v, String fallback) => _sOrNull(v) ?? fallback;
List<String> _strings(Object? v) =>
    [for (final e in (v as List<dynamic>? ?? const [])) e.toString()];

/// How the participant talks to the avatar.
enum LiveInputMode {
  typed('typed', 'Type'),
  speech('speech', 'Speak');

  const LiveInputMode(this.wire, this.label);
  final String wire;
  final String label;

  static LiveInputMode? maybeFromWire(Object? value) {
    for (final m in values) {
      if (m.wire == value) return m;
    }
    return null;
  }

  /// The known modes in [value], in the order sent, without repeats.
  static List<LiveInputMode> listFromJson(Object? value) {
    final out = <LiveInputMode>[];
    for (final e in (value as List<dynamic>? ?? const [])) {
      final m = maybeFromWire(e);
      if (m != null && !out.contains(m)) out.add(m);
    }
    return out;
  }
}

/// Why a conversation closed (`end_reason`).
abstract final class LiveEndReason {
  /// The participant asked to stop (said so in the conversation).
  static const participant = 'participant';

  /// The participant pressed "End conversation".
  static const participantEnded = 'participant_ended';
  static const turnLimit = 'turn_limit';
  static const timeLimit = 'time_limit';
  static const budget = 'budget';
  static const sessionEnded = 'session_ended';
}

/// Plain wording for an end reason, or an empty string when there is none.
String liveEndReasonLabel(String? reason) => switch (reason) {
      null || '' => '',
      LiveEndReason.participant => 'You asked to stop',
      LiveEndReason.participantEnded => 'You ended the conversation',
      LiveEndReason.turnLimit => 'All the turns were used',
      LiveEndReason.timeLimit => 'The time for the conversation was up',
      LiveEndReason.budget => 'The conversation stopped early',
      LiveEndReason.sessionEnded => 'The session ended',
      _ => () {
          final text = reason.replaceAll('_', ' ');
          return text[0].toUpperCase() + text.substring(1);
        }(),
    };

/// Fills `{{display_name}}` and `{{topic}}` in one of the protocol's lines the
/// way the server does (a missing name becomes "there"), so the app can show
/// the same closing line when the server's answer comes without its text.
String renderLiveLine(String template,
    {String? displayName, required String topic}) {
  final name = (displayName ?? '').trim();
  final text = template
      .replaceAll('{{display_name}}', name.isEmpty ? 'there' : name)
      .replaceAll('{{topic}}', topic)
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAllMapped(RegExp(r'\s+([,.!?])'), (m) => m[1]!);
  return text.trim();
}

/// Flags the server puts on turns (the ones the apps look at).
abstract final class LiveFlag {
  static const typed = 'typed';
  static const speech = 'speech';
  static const sampleSpeech = 'sample_speech';
  static const participantTruncated = 'participant_truncated';
  static const participantOnTopic = 'participant_on_topic';
  static const participantOffTopic = 'participant_off_topic';
  static const distress = 'distress';
  static const scriptedLine = 'scripted_line';
  static const opening = 'opening';
  static const closing = 'closing';
  static const redirectLine = 'redirect_line';
  static const fallbackLine = 'fallback_line';
  static const participantWantsToStop = 'participant_wants_to_stop';
}

/// One line of the conversation. [text] is null once the server removed it
/// (the conversation closed without a kept transcript) or when the viewer may
/// not see it.
class LiveTurn {
  const LiveTurn({
    required this.index,
    required this.role,
    this.text,
    this.chars = 0,
    this.tMs,
    this.flags = const [],
    this.latencyMs,
  });

  final int index;

  /// `avatar` or `participant`.
  final String role;
  final String? text;
  final int chars;
  final int? tMs;
  final List<String> flags;
  final int? latencyMs;

  bool get isAvatar => role == 'avatar';
  bool get isParticipant => role == 'participant';
  bool hasFlag(String flag) => flags.contains(flag);

  static LiveTurn? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return LiveTurn(
      index: _i(value['index'], 0),
      role: _s(value['role'], 'avatar'),
      text: value['text']?.toString(),
      chars: _i(value['chars'], 0),
      tMs: (value['t_ms'] as num?)?.toInt(),
      flags: _strings(value['flags']),
      latencyMs: (value['latency_ms'] as num?)?.toInt(),
    );
  }

  static List<LiveTurn> listFromJson(Object? value) => [
        for (final e in (value as List<dynamic>? ?? const []))
          ?LiveTurn.maybeFromJson(e),
      ];
}

/// Which providers a conversation runs on (names, for the research team).
class LiveProviders {
  const LiveProviders({this.reply = '', this.speech = '', this.avatar = ''});

  final String reply;
  final String speech;
  final String avatar;

  factory LiveProviders.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const LiveProviders();
    return LiveProviders(
      reply: _s(value['reply'], ''),
      speech: _s(value['speech'], ''),
      avatar: _s(value['avatar'], ''),
    );
  }
}

abstract final class ConversationStatus {
  static const open = 'open';
  static const closed = 'closed';
}

/// The conversation of a session.
class LiveConversation {
  const LiveConversation({
    required this.id,
    this.status = ConversationStatus.open,
    this.topic = '',
    this.inputMode = LiveInputMode.typed,
    this.transcriptAllowed = false,
    this.turnsUsed = 0,
    this.turnsLeft = 0,
    this.endReason,
    this.startedAt,
    this.endedAt,
    this.providers = const LiveProviders(),
  });

  final String id;

  /// `open` or `closed`.
  final String status;
  final String topic;
  final LiveInputMode inputMode;

  /// True only when the protocol keeps transcripts and the participant agreed.
  final bool transcriptAllowed;
  final int turnsUsed;
  final int turnsLeft;
  final String? endReason;
  final String? startedAt;
  final String? endedAt;
  final LiveProviders providers;

  bool get isOpen => status == ConversationStatus.open;
  bool get isClosed => status == ConversationStatus.closed;

  static LiveConversation? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return LiveConversation(
      id: value['id']?.toString() ?? '',
      status: _s(value['status'], ConversationStatus.open),
      topic: _s(value['topic'], ''),
      inputMode:
          LiveInputMode.maybeFromWire(value['input_mode']) ?? LiveInputMode.typed,
      transcriptAllowed: _b(value['transcript_allowed'], false),
      turnsUsed: _i(value['turns_used'], 0),
      turnsLeft: _i(value['turns_left'], 0),
      endReason: _sOrNull(value['end_reason']),
      startedAt: _sOrNull(value['started_at']),
      endedAt: _sOrNull(value['ended_at']),
      providers: LiveProviders.fromJson(value['providers']),
    );
  }
}

/// The limits the protocol sets for the conversation.
class LiveLimits {
  const LiveLimits({
    this.maxTurns = 8,
    this.maxMinutes = 8,
    this.maxReplyWords = 40,
    this.maxParticipantChars = 400,
    this.inputModes = const [LiveInputMode.typed, LiveInputMode.speech],
  });

  final int maxTurns;
  final int maxMinutes;
  final int maxReplyWords;
  final int maxParticipantChars;
  final List<LiveInputMode> inputModes;

  bool get offersSpeech => inputModes.contains(LiveInputMode.speech);

  factory LiveLimits.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const LiveLimits();
    final modes = LiveInputMode.listFromJson(value['input_modes']);
    return LiveLimits(
      maxTurns: _i(value['max_turns'], 8),
      maxMinutes: _i(value['max_minutes'], 8),
      maxReplyWords: _i(value['max_reply_words'], 40),
      maxParticipantChars: _i(value['max_participant_chars'], 400),
      inputModes: modes.isEmpty ? const [LiveInputMode.typed] : modes,
    );
  }
}

/// How the avatar is shown. The development value is a sample video that
/// loops, with every line as a caption and the browser's own voice.
class LiveAvatar {
  const LiveAvatar({
    this.mode = 'sample_video',
    this.videoUrl,
    this.voice = 'browser_tts',
    this.captions = true,
    this.synthetic = false,
    this.note,
  });

  final String mode;

  /// As the server sent it; resolve it against the service address.
  final String? videoUrl;
  final String voice;
  final bool captions;
  final bool synthetic;
  final String? note;

  /// The browser speaks the lines (there is no avatar voice of its own).
  bool get usesBrowserVoice => voice == 'browser_tts';

  factory LiveAvatar.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const LiveAvatar();
    return LiveAvatar(
      mode: _s(value['mode'], 'sample_video'),
      videoUrl: _sOrNull(value['video_url']),
      voice: _s(value['voice'], 'browser_tts'),
      captions: _b(value['captions'], true),
      synthetic: _b(value['synthetic'], false),
      note: _sOrNull(value['note']),
    );
  }

  LiveAvatar copyWith({String? videoUrl}) => LiveAvatar(
        mode: mode,
        videoUrl: videoUrl ?? this.videoUrl,
        voice: voice,
        captions: captions,
        synthetic: synthetic,
        note: note,
      );
}

/// `GET /me/sessions/{sid}/live`: where the conversation stands, or nothing
/// yet, plus what the participant may choose before starting.
class LiveSnapshot {
  const LiveSnapshot({
    this.conversation,
    this.turns = const [],
    this.limits = const LiveLimits(),
    this.storeTranscriptOffered = false,
    this.inputModes = const [LiveInputMode.typed],
  });

  final LiveConversation? conversation;
  final List<LiveTurn> turns;
  final LiveLimits limits;

  /// The protocol keeps transcripts: the participant is asked to agree.
  final bool storeTranscriptOffered;
  final List<LiveInputMode> inputModes;

  bool get offersSpeech => inputModes.contains(LiveInputMode.speech);

  factory LiveSnapshot.fromJson(Map<String, dynamic> json) {
    final limits = LiveLimits.fromJson(json['limits']);
    final modes = LiveInputMode.listFromJson(json['input_modes']);
    return LiveSnapshot(
      conversation: LiveConversation.maybeFromJson(json['conversation']),
      turns: LiveTurn.listFromJson(json['turns']),
      limits: limits,
      storeTranscriptOffered: _b(json['store_transcript_offered'], false),
      inputModes: modes.isEmpty ? limits.inputModes : modes,
    );
  }
}

/// `POST /me/sessions/{sid}/live/start`.
class LiveStart {
  const LiveStart({
    required this.conversation,
    this.turns = const [],
    this.avatar = const LiveAvatar(),
    this.faceLayout,
    this.limits = const LiveLimits(),
    this.resumed = false,
  });

  final LiveConversation conversation;

  /// The opening line, or the whole conversation so far when [resumed].
  final List<LiveTurn> turns;
  final LiveAvatar avatar;

  /// Face, eye and mouth regions as fractions of the avatar frame; null when
  /// the protocol has none (the gaze is then not classified by region).
  final NormalizedFaceLayout? faceLayout;
  final LiveLimits limits;
  final bool resumed;

  factory LiveStart.fromJson(Map<String, dynamic> json) => LiveStart(
        conversation: LiveConversation.maybeFromJson(json['conversation']) ??
            const LiveConversation(id: ''),
        turns: LiveTurn.listFromJson(json['turns']),
        avatar: LiveAvatar.fromJson(json['avatar']),
        faceLayout: NormalizedFaceLayout.maybeFromJson(json['face_layout']),
        limits: LiveLimits.fromJson(json['limits']),
        resumed: _b(json['resumed'], false),
      );
}

/// `POST .../live/turn` and `.../live/turn-audio`.
class LiveTurnResult {
  const LiveTurnResult({
    this.participant,
    required this.avatar,
    this.turnsUsed = 0,
    this.turnsLeft = 0,
    this.done = false,
    this.endReason,
    this.distress = false,
  });

  /// What the server understood the participant said (the transcript of a
  /// spoken turn); null when the turn was refused as over time or budget.
  final LiveTurn? participant;
  final LiveTurn avatar;
  final int turnsUsed;
  final int turnsLeft;
  final bool done;
  final String? endReason;

  /// The participant seemed uncomfortable: offer a break.
  final bool distress;

  factory LiveTurnResult.fromJson(Map<String, dynamic> json) => LiveTurnResult(
        participant: LiveTurn.maybeFromJson(json['participant']),
        avatar: LiveTurn.maybeFromJson(json['avatar']) ??
            const LiveTurn(index: 0, role: 'avatar'),
        turnsUsed: _i(json['turns_used'], 0),
        turnsLeft: _i(json['turns_left'], 0),
        done: _b(json['done'], false),
        endReason: _sOrNull(json['end_reason']),
        distress: _b(json['distress'], false),
      );
}

/// `POST .../live/end`.
class LiveEndResult {
  const LiveEndResult({
    required this.avatar,
    this.turnsUsed = 0,
    this.done = true,
    this.endReason,
  });

  final LiveTurn avatar;
  final int turnsUsed;
  final bool done;
  final String? endReason;

  factory LiveEndResult.fromJson(Map<String, dynamic> json) => LiveEndResult(
        avatar: LiveTurn.maybeFromJson(json['avatar']) ??
            const LiveTurn(index: 0, role: 'avatar'),
        turnsUsed: _i(json['turns_used'], 0),
        done: _b(json['done'], true),
        endReason: _sOrNull(json['end_reason']),
      );
}

/// `outcomes.conversation` of a session summary: counts and the reply
/// model's on-topic judgement. The share describes the conversation, not
/// understanding, and is judged by the reply model.
class ConversationOutcome {
  const ConversationOutcome({
    this.participantTurns = 0,
    this.avatarTurns = 0,
    this.onTopic = 0,
    this.onTopicShare,
    this.redirects = 0,
    this.distress = 0,
    this.endReason,
    this.note,
  });

  final int participantTurns;
  final int avatarTurns;
  final int onTopic;

  /// Null when no turn was judged.
  final double? onTopicShare;
  final int redirects;
  final int distress;
  final String? endReason;
  final String? note;

  static ConversationOutcome? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return ConversationOutcome(
      participantTurns: _i(value['participant_turns'], 0),
      avatarTurns: _i(value['avatar_turns'], 0),
      onTopic: _i(value['on_topic'], 0),
      onTopicShare: _dOrNull(value['on_topic_share']),
      redirects: _i(value['redirects'], 0),
      distress: _i(value['distress'], 0),
      endReason: _sOrNull(value['end_reason']),
      note: _sOrNull(value['note']),
    );
  }
}

/// The `live` section of a `live_conversation` protocol version, as the
/// researcher edits it and the server freezes it.
class LiveProtocolConfig {
  const LiveProtocolConfig({
    this.maxTurns = 8,
    this.maxMinutes = 8,
    this.maxReplyWords = 40,
    this.maxParticipantChars = 400,
    this.openingLine = defaultOpeningLine,
    this.closingLine = defaultClosingLine,
    this.redirectLine = defaultRedirectLine,
    this.distressLine = defaultDistressLine,
    this.avatarId = '',
    this.voiceId = '',
    this.inputModes = const [LiveInputMode.typed, LiveInputMode.speech],
    this.storeTranscript = false,
    this.faceLayout,
  });

  static const defaultOpeningLine =
      "Hi {{display_name}}! I'd love to hear about {{topic}}. "
      'What do you like most about it?';
  static const defaultClosingLine =
      'Thank you for talking with me about {{topic}}, {{display_name}}. '
      'I enjoyed it.';
  static const defaultRedirectLine =
      "Let's keep talking about {{topic}}. What else do you like about it?";
  static const defaultDistressLine =
      'Thank you for telling me. We can take a break whenever you like. '
      'Would you like to pause for a moment?';

  final int maxTurns;
  final int maxMinutes;
  final int maxReplyWords;
  final int maxParticipantChars;
  final String openingLine;
  final String closingLine;
  final String redirectLine;
  final String distressLine;
  final String avatarId;
  final String voiceId;
  final List<LiveInputMode> inputModes;
  final bool storeTranscript;

  /// Regions of the avatar frame as fractions; null when not set.
  final NormalizedFaceLayout? faceLayout;

  factory LiveProtocolConfig.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const LiveProtocolConfig();
    final modes = LiveInputMode.listFromJson(value['input_modes']);
    return LiveProtocolConfig(
      maxTurns: _i(value['max_turns'], 8),
      maxMinutes: _i(value['max_minutes'], 8),
      maxReplyWords: _i(value['max_reply_words'], 40),
      maxParticipantChars: _i(value['max_participant_chars'], 400),
      openingLine: _s(value['opening_line'], defaultOpeningLine),
      closingLine: _s(value['closing_line'], defaultClosingLine),
      redirectLine: _s(value['redirect_line'], defaultRedirectLine),
      distressLine: _s(value['distress_line'], defaultDistressLine),
      avatarId: value['avatar_id']?.toString() ?? '',
      voiceId: value['voice_id']?.toString() ?? '',
      inputModes: modes.isEmpty
          ? const [LiveInputMode.typed, LiveInputMode.speech]
          : modes,
      storeTranscript: _b(value['store_transcript'], false),
      faceLayout: NormalizedFaceLayout.maybeFromJson(value['face_layout']),
    );
  }

  Map<String, dynamic> toJson() => {
        'max_turns': maxTurns,
        'max_minutes': maxMinutes,
        'max_reply_words': maxReplyWords,
        'max_participant_chars': maxParticipantChars,
        'opening_line': openingLine,
        'closing_line': closingLine,
        'redirect_line': redirectLine,
        'distress_line': distressLine,
        'avatar_id': avatarId,
        'voice_id': voiceId,
        'input_modes': [for (final m in inputModes) m.wire],
        'store_transcript': storeTranscript,
        if (faceLayout != null) 'face_layout': faceLayout!.toJson(),
      };

  LiveProtocolConfig copyWith({
    int? maxTurns,
    int? maxMinutes,
    int? maxReplyWords,
    int? maxParticipantChars,
    String? openingLine,
    String? closingLine,
    String? redirectLine,
    String? distressLine,
    String? avatarId,
    String? voiceId,
    List<LiveInputMode>? inputModes,
    bool? storeTranscript,
    NormalizedFaceLayout? faceLayout,
    bool clearFaceLayout = false,
  }) =>
      LiveProtocolConfig(
        maxTurns: maxTurns ?? this.maxTurns,
        maxMinutes: maxMinutes ?? this.maxMinutes,
        maxReplyWords: maxReplyWords ?? this.maxReplyWords,
        maxParticipantChars: maxParticipantChars ?? this.maxParticipantChars,
        openingLine: openingLine ?? this.openingLine,
        closingLine: closingLine ?? this.closingLine,
        redirectLine: redirectLine ?? this.redirectLine,
        distressLine: distressLine ?? this.distressLine,
        avatarId: avatarId ?? this.avatarId,
        voiceId: voiceId ?? this.voiceId,
        inputModes: inputModes ?? this.inputModes,
        storeTranscript: storeTranscript ?? this.storeTranscript,
        faceLayout: clearFaceLayout ? null : (faceLayout ?? this.faceLayout),
      );
}

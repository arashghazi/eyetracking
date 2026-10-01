import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:research_admin/features/live/domain/live_models.dart';

import 'fakes.dart';

/// `GET /studies/{id}/live/status` with the development providers.
Map<String, dynamic> liveStatusJson({
  Map<String, dynamic>? reply,
  Map<String, dynamic>? speech,
  Map<String, dynamic>? avatar,
  int open = 2,
}) =>
    {
      'reply_provider': reply ??
          {'name': 'fake', 'configured': true, 'synthetic': true},
      'speech_provider': speech ??
          {'name': 'fake', 'configured': true, 'synthetic': true},
      'avatar_provider': avatar ??
          {
            'name': 'fake',
            'configured': true,
            'synthetic': true,
            'streaming': false,
          },
      'estimates': {'per_turn_units': 0.012, 'avatar_per_minute_units': 0},
      'budget': {
        'cost_cap_units': 5.0,
        'spent_units': 1.25,
        'remaining_units': 3.75,
        'send_free_text': true,
      },
      'open_conversations': open,
      'note': 'Development providers are synthetic: sample rules, a sample '
          "face video and the browser's voice. No streaming avatar is "
          'connected.',
    };

LiveAvatarStatus sampleLiveStatus() =>
    LiveAvatarStatus.fromJson(liveStatusJson());

/// The provider status of a study that uses Claude and a local Whisper.
LiveAvatarStatus claudeLiveStatus({bool replyConfigured = true}) =>
    LiveAvatarStatus.fromJson(liveStatusJson(
      reply: {
        'name': 'anthropic',
        'model': 'claude-opus-5-5',
        'effort': 'low',
        'configured': replyConfigured,
        'synthetic': false,
      },
      speech: {
        'name': 'whisper_http',
        'model': 'base',
        'base_url': 'http://127.0.0.1:8200',
        'configured': true,
        'synthetic': false,
      },
      avatar: {
        'name': 'streaming-vendor',
        'configured': true,
        'synthetic': false,
        'streaming': true,
      },
    ));

Map<String, dynamic> turnJson(
  int index,
  String role,
  String? text, {
  List<String> flags = const [],
  int? tMs,
}) =>
    {
      'index': index,
      'role': role,
      'text': text,
      'chars': text?.length ?? 40,
      't_ms': tMs ?? 1000 * (index + 1),
      'flags': flags,
      'latency_ms': role == 'avatar' ? 420 : null,
    };

/// The answer of `GET .../conversation`. With [withText] the transcript was
/// kept; without it every turn's text is null.
Map<String, dynamic> conversationJson({
  bool withText = false,
  bool open = false,
  int distress = 0,
}) {
  String? text(String t) => withText ? t : null;
  return {
    'conversation': {
      'id': 5,
      'status': open ? 'open' : 'closed',
      'topic': 'trains',
      'input_mode': 'speech',
      'transcript_allowed': withText,
      'turns_used': 3,
      'turns_left': open ? 5 : 0,
      'end_reason': open ? null : 'participant_ended',
      'started_at': '2026-09-30T09:05:00',
      'ended_at': open ? null : '2026-09-30T09:12:00',
      'providers': {'reply': 'fake', 'speech': 'fake', 'avatar': 'fake'},
    },
    'turns': [
      turnJson(0, 'avatar', text('Hi Sam! Tell me about trains.'),
          flags: ['scripted_line', 'opening']),
      turnJson(1, 'participant', text('I like steam trains'),
          flags: ['speech', 'participant_on_topic']),
      turnJson(2, 'avatar', text('Steam trains are fun. Which one is your favourite?'),
          flags: const []),
      turnJson(3, 'participant', text('I feel scared'),
          flags: ['typed', 'participant_off_topic', if (distress > 0) 'distress']),
      turnJson(4, 'avatar', text('Thank you for telling me. Would you like a break?'),
          flags: ['scripted_line', 'redirect_line']),
    ],
    'outcome': {
      'participant_turns': 2,
      'avatar_turns': 3,
      'on_topic': 1,
      'on_topic_share': 0.5,
      'redirects': 1,
      'distress': distress,
      'end_reason': open ? null : 'participant_ended',
      'note': 'On-topic judgements come from the reply model; they describe '
          'the conversation, not understanding.',
    },
    'cost_units': 0.0361,
    'note': 'Text is shown only when the protocol keeps transcripts and the '
        'participant agreed. Audio is never kept.',
  };
}

StaffConversation sampleConversation({
  bool withText = false,
  bool open = false,
  int distress = 0,
}) =>
    StaffConversation.fromJson(
      conversationJson(withText: withText, open: open, distress: distress),
    );

/// The `conversation` block of the live monitor.
ConversationMonitor sampleMonitor({
  String status = 'open',
  int distress = 0,
  int redirects = 1,
  bool lastTurn = true,
  String? endReason,
}) =>
    ConversationMonitor.maybeFromJson({
      'status': status,
      'input_mode': 'speech',
      'turns_used': 3,
      'distress': distress,
      'redirects': redirects,
      'last_turn': lastTurn
          ? {
              'role': 'avatar',
              'flags': ['scripted_line', 'redirect_line'],
              't_ms': 83500,
            }
          : null,
      'end_reason': endReason,
    })!;

/// A protocol of the live path, as the fake repository holds it.
ProtocolDetail liveProtocol(
  String id,
  String name, {
  int version = 0,
  String status = ProtocolStatus.draft,
  LiveProtocolConfig config = const LiveProtocolConfig(),
}) =>
    ProtocolDetail(
      summary: protocolRow(
        id,
        name,
        version: version,
        status: status,
        path: ProtocolPath.liveConversation,
      ),
      definition: ProtocolDefinition(
        path: ProtocolPath.liveConversation,
        live: config,
      ),
    );

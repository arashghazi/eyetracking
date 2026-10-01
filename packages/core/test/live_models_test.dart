import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _turnJson = <String, dynamic>{
  'index': 1,
  'role': 'participant',
  'text': 'I like trains',
  'chars': 13,
  't_ms': 4200,
  'flags': ['typed', 'participant_on_topic'],
  'latency_ms': null,
};

const _conversationJson = <String, dynamic>{
  'id': 4,
  'status': 'open',
  'topic': 'trains',
  'input_mode': 'speech',
  'transcript_allowed': true,
  'turns_used': 2,
  'turns_left': 6,
  'end_reason': null,
  'started_at': '2026-10-01T09:00:00',
  'ended_at': null,
  'providers': {'reply': 'fake', 'speech': 'fake', 'avatar': 'fake'},
};

const _limitsJson = <String, dynamic>{
  'max_turns': 8,
  'max_minutes': 8,
  'max_reply_words': 40,
  'max_participant_chars': 400,
  'input_modes': ['typed', 'speech'],
};

const _avatarJson = <String, dynamic>{
  'mode': 'sample_video',
  'video_url': '/static/live/sample-face.webm',
  'voice': 'browser_tts',
  'captions': true,
  'synthetic': true,
  'note': 'Development avatar',
};

const _layoutJson = <String, dynamic>{
  'face_box': [0.3, 0.1, 0.4, 0.8],
  'eye_region': [0.3, 0.25, 0.4, 0.2],
  'mouth_region': [0.3, 0.55, 0.4, 0.25],
};

void main() {
  group('LiveTurn', () {
    test('parses the contract shape and its flags', () {
      final t = LiveTurn.maybeFromJson(_turnJson)!;
      expect(t.index, 1);
      expect(t.isParticipant, isTrue);
      expect(t.isAvatar, isFalse);
      expect(t.text, 'I like trains');
      expect(t.tMs, 4200);
      expect(t.latencyMs, isNull);
      expect(t.hasFlag(LiveFlag.participantOnTopic), isTrue);
      expect(t.hasFlag(LiveFlag.distress), isFalse);
    });

    test('keeps a removed text as null and ignores non-objects', () {
      final t = LiveTurn.maybeFromJson(
          {'index': 0, 'role': 'avatar', 'text': null, 'chars': 40})!;
      expect(t.text, isNull);
      expect(t.chars, 40);
      expect(t.flags, isEmpty);
      expect(LiveTurn.maybeFromJson('x'), isNull);
      expect(LiveTurn.listFromJson([_turnJson, 'x', null]).length, 1);
      expect(LiveTurn.listFromJson(null), isEmpty);
    });
  });

  group('LiveConversation', () {
    test('parses the conversation block', () {
      final c = LiveConversation.maybeFromJson(_conversationJson)!;
      expect(c.id, '4');
      expect(c.isOpen, isTrue);
      expect(c.isClosed, isFalse);
      expect(c.topic, 'trains');
      expect(c.inputMode, LiveInputMode.speech);
      expect(c.transcriptAllowed, isTrue);
      expect(c.turnsUsed, 2);
      expect(c.turnsLeft, 6);
      expect(c.endReason, isNull);
      expect(c.providers.reply, 'fake');
      expect(c.providers.speech, 'fake');
    });

    test('a closed conversation carries its end reason', () {
      final c = LiveConversation.maybeFromJson({
        ..._conversationJson,
        'status': 'closed',
        'end_reason': 'turn_limit',
        'ended_at': '2026-10-01T09:05:00',
      })!;
      expect(c.isClosed, isTrue);
      expect(c.endReason, LiveEndReason.turnLimit);
      expect(c.endedAt, isNotNull);
    });

    test('is null when the server sent none, typed when the mode is unknown', () {
      expect(LiveConversation.maybeFromJson(null), isNull);
      final c = LiveConversation.maybeFromJson({'id': 1, 'input_mode': 'telepathy'})!;
      expect(c.inputMode, LiveInputMode.typed);
      expect(c.isOpen, isTrue);
    });
  });

  group('LiveLimits and LiveInputMode', () {
    test('parse the limits and offer speech only when listed', () {
      final l = LiveLimits.fromJson(_limitsJson);
      expect(l.maxTurns, 8);
      expect(l.maxParticipantChars, 400);
      expect(l.offersSpeech, isTrue);
      final typedOnly = LiveLimits.fromJson({
        ..._limitsJson,
        'input_modes': ['typed'],
      });
      expect(typedOnly.offersSpeech, isFalse);
    });

    test('unknown modes are dropped and typing is the fallback', () {
      expect(LiveInputMode.listFromJson(['speech', 'x', 'speech', 'typed']),
          [LiveInputMode.speech, LiveInputMode.typed]);
      expect(LiveLimits.fromJson({'input_modes': ['x']}).inputModes,
          [LiveInputMode.typed]);
      expect(LiveLimits.fromJson(null).maxTurns, 8);
    });
  });

  group('LiveAvatar', () {
    test('parses the development avatar and resolves nothing itself', () {
      final a = LiveAvatar.fromJson(_avatarJson);
      expect(a.mode, 'sample_video');
      expect(a.videoUrl, '/static/live/sample-face.webm');
      expect(a.usesBrowserVoice, isTrue);
      expect(a.captions, isTrue);
      expect(a.synthetic, isTrue);
      expect(a.note, 'Development avatar');
      final moved = a.copyWith(videoUrl: 'http://x/y.webm');
      expect(moved.videoUrl, 'http://x/y.webm');
      expect(moved.synthetic, isTrue);
    });

    test('missing fields give a plain, non-synthetic avatar', () {
      final a = LiveAvatar.fromJson(null);
      expect(a.videoUrl, isNull);
      expect(a.synthetic, isFalse);
    });
  });

  group('responses', () {
    test('start: conversation, opening turn, avatar, layout and limits', () {
      final s = LiveStart.fromJson({
        'conversation': _conversationJson,
        'turns': [
          {
            'index': 0,
            'role': 'avatar',
            'text': 'Hi Sam!',
            'chars': 7,
            'flags': ['scripted_line', 'opening'],
          },
        ],
        'avatar': _avatarJson,
        'face_layout': _layoutJson,
        'limits': _limitsJson,
        'resumed': true,
      });
      expect(s.conversation.id, '4');
      expect(s.turns.single.text, 'Hi Sam!');
      expect(s.turns.single.hasFlag(LiveFlag.opening), isTrue);
      expect(s.avatar.synthetic, isTrue);
      expect(s.faceLayout!.eyeRegion, const Box(0.3, 0.25, 0.4, 0.2));
      expect(s.limits.maxTurns, 8);
      expect(s.resumed, isTrue);
    });

    test('start without a face layout leaves it null', () {
      final s = LiveStart.fromJson({
        'conversation': _conversationJson,
        'turns': const [],
        'avatar': _avatarJson,
        'face_layout': null,
        'limits': _limitsJson,
        'resumed': false,
      });
      expect(s.faceLayout, isNull);
      expect(s.resumed, isFalse);
    });

    test('snapshot: nothing started yet, and what may be chosen', () {
      final s = LiveSnapshot.fromJson({
        'conversation': null,
        'turns': const [],
        'limits': _limitsJson,
        'store_transcript_offered': true,
        'input_modes': ['typed'],
      });
      expect(s.conversation, isNull);
      expect(s.storeTranscriptOffered, isTrue);
      expect(s.offersSpeech, isFalse);
      expect(s.limits.maxTurns, 8);
    });

    test('snapshot: an open conversation with its turns', () {
      final s = LiveSnapshot.fromJson({
        'conversation': _conversationJson,
        'turns': [_turnJson],
        'limits': _limitsJson,
        'store_transcript_offered': false,
        'input_modes': ['typed', 'speech'],
      });
      expect(s.conversation!.isOpen, isTrue);
      expect(s.turns.single.text, 'I like trains');
      expect(s.offersSpeech, isTrue);
      expect(s.storeTranscriptOffered, isFalse);
    });

    test('turn result: participant, avatar, counts, done and distress', () {
      final r = LiveTurnResult.fromJson({
        'participant': _turnJson,
        'avatar': {
          'index': 2,
          'role': 'avatar',
          'text': 'Trains are great.',
          'chars': 17,
          'flags': ['distress', 'scripted_line'],
          't_ms': 4300,
          'latency_ms': 120,
        },
        'turns_used': 1,
        'turns_left': 7,
        'done': false,
        'end_reason': null,
        'distress': true,
      });
      expect(r.participant!.text, 'I like trains');
      expect(r.avatar.text, 'Trains are great.');
      expect(r.avatar.latencyMs, 120);
      expect(r.turnsUsed, 1);
      expect(r.turnsLeft, 7);
      expect(r.done, isFalse);
      expect(r.distress, isTrue);
      expect(r.endReason, isNull);
    });

    test('a refused turn has no participant line and is done', () {
      final r = LiveTurnResult.fromJson({
        'participant': null,
        'avatar': {'index': 3, 'role': 'avatar', 'text': 'Thank you.'},
        'turns_used': 4,
        'turns_left': 0,
        'done': true,
        'end_reason': 'time_limit',
        'distress': false,
      });
      expect(r.participant, isNull);
      expect(r.done, isTrue);
      expect(r.endReason, LiveEndReason.timeLimit);
    });

    test('end result', () {
      final r = LiveEndResult.fromJson({
        'avatar': {'index': 5, 'role': 'avatar', 'text': 'Bye'},
        'turns_used': 3,
        'done': true,
        'end_reason': 'participant_ended',
      });
      expect(r.avatar.text, 'Bye');
      expect(r.turnsUsed, 3);
      expect(r.done, isTrue);
      expect(r.endReason, LiveEndReason.participantEnded);
    });
  });

  group('renderLiveLine', () {
    test('fills name and topic and tidies the spaces like the server', () {
      expect(
        renderLiveLine('Hi {{display_name}}! Let us talk about {{topic}}.',
            displayName: 'Sam', topic: 'trains'),
        'Hi Sam! Let us talk about trains.',
      );
      expect(
        renderLiveLine('Thank you, {{display_name}} .',
            displayName: '  ', topic: 'x'),
        'Thank you, there.',
      );
      expect(renderLiveLine('Hello {{topic}}', topic: 'space'), 'Hello space');
    });
  });

  group('end reasons', () {
    test('have plain wording; unknown ones are made readable', () {
      expect(liveEndReasonLabel(null), '');
      expect(liveEndReasonLabel('participant'), 'You asked to stop');
      expect(liveEndReasonLabel('participant_ended'), 'You ended the conversation');
      expect(liveEndReasonLabel('turn_limit'), 'All the turns were used');
      expect(liveEndReasonLabel('time_limit'), 'The time for the conversation was up');
      expect(liveEndReasonLabel('budget'), 'The conversation stopped early');
      expect(liveEndReasonLabel('session_ended'), 'The session ended');
      expect(liveEndReasonLabel('something_new'), 'Something new');
    });
  });

  group('ConversationOutcome', () {
    test('parses the summary block, share null when nothing was judged', () {
      final o = ConversationOutcome.maybeFromJson({
        'participant_turns': 4,
        'avatar_turns': 5,
        'on_topic': 3,
        'on_topic_share': 0.75,
        'redirects': 1,
        'distress': 0,
        'end_reason': 'turn_limit',
        'note': 'On-topic judgements come from the reply model.',
      })!;
      expect(o.participantTurns, 4);
      expect(o.onTopic, 3);
      expect(o.onTopicShare, 0.75);
      expect(o.redirects, 1);
      expect(o.endReason, 'turn_limit');
      expect(o.note, contains('reply model'));
      final none = ConversationOutcome.maybeFromJson({
        'participant_turns': 0,
        'avatar_turns': 1,
        'on_topic': 0,
        'on_topic_share': null,
        'redirects': 0,
        'distress': 0,
        'end_reason': null,
      })!;
      expect(none.onTopicShare, isNull);
      expect(none.endReason, isNull);
      expect(ConversationOutcome.maybeFromJson(null), isNull);
    });

    test('is part of the session outcomes, null on the other paths', () {
      final live = SessionOutcomes.maybeFromJson({
        'gaze': {'evaluable': false},
        'conversation': {
          'participant_turns': 2,
          'avatar_turns': 3,
          'on_topic': 2,
          'on_topic_share': 1.0,
          'redirects': 0,
          'distress': 0,
          'end_reason': 'participant_ended',
        },
      })!;
      expect(live.conversation!.participantTurns, 2);
      expect(live.conversation!.onTopicShare, 1.0);
      final other = SessionOutcomes.maybeFromJson({
        'gaze': {'evaluable': false},
        'conversation': null,
      })!;
      expect(other.conversation, isNull);
      expect(SessionOutcomes.maybeFromJson(<String, dynamic>{})!.conversation, isNull);
    });
  });

  group('live_conversation protocol', () {
    const liveDefinition = <String, dynamic>{
      'path': 'live_conversation',
      'baseline_seconds': 20,
      'post_seconds': 15,
      'comfort': {'scale_max': 5, 'min_ok': 3, 'ask_every_stage': true},
      'progression': {
        'hold_on_invalid_share_above': 0.3,
        'easier_on_comfort_below_min': true,
        'stop_on_two_low_comfort': true,
      },
      'live': {
        'max_turns': 6,
        'max_minutes': 5,
        'max_reply_words': 30,
        'max_participant_chars': 300,
        'opening_line': 'Hello {{display_name}}',
        'closing_line': 'Bye {{display_name}}',
        'redirect_line': 'Back to {{topic}}',
        'distress_line': 'Take a break?',
        'avatar_id': 'a1',
        'voice_id': 'v1',
        'input_modes': ['typed'],
        'store_transcript': true,
        'face_layout': _layoutJson,
      },
    };

    test('the path is a ProtocolPath with its wire name', () {
      expect(ProtocolPath.maybeFromWire('live_conversation'),
          ProtocolPath.liveConversation);
      expect(ProtocolPath.liveConversation.wire, 'live_conversation');
      expect(ProtocolPath.liveConversation.label, isNotEmpty);
    });

    test('the definition carries the live settings and round-trips', () {
      final def = ProtocolDefinition.maybeFromJson(liveDefinition)!;
      expect(def.path, ProtocolPath.liveConversation);
      expect(def.gradual, isNull);
      expect(def.interest, isNull);
      final live = def.live!;
      expect(live.maxTurns, 6);
      expect(live.maxMinutes, 5);
      expect(live.maxReplyWords, 30);
      expect(live.maxParticipantChars, 300);
      expect(live.openingLine, 'Hello {{display_name}}');
      expect(live.avatarId, 'a1');
      expect(live.inputModes, [LiveInputMode.typed]);
      expect(live.storeTranscript, isTrue);
      expect(live.faceLayout!.faceBox, const Box(0.3, 0.1, 0.4, 0.8));
      final again = def.toJson();
      expect(again['path'], 'live_conversation');
      final liveJson = again['live'] as Map<String, dynamic>;
      expect(liveJson['max_turns'], 6);
      expect(liveJson['input_modes'], ['typed']);
      expect(liveJson['store_transcript'], true);
      expect(liveJson['face_layout'], _layoutJson);
      expect(again.containsKey('gradual'), isFalse);
      expect(again.containsKey('interest'), isFalse);
    });

    test('defaults match the server and the starter has live settings', () {
      final live = ProtocolDefinition.starter(ProtocolPath.liveConversation).live!;
      expect(live.maxTurns, 8);
      expect(live.maxMinutes, 8);
      expect(live.maxReplyWords, 40);
      expect(live.maxParticipantChars, 400);
      expect(live.storeTranscript, isFalse);
      expect(live.inputModes, [LiveInputMode.typed, LiveInputMode.speech]);
      expect(live.openingLine, contains('{{topic}}'));
      expect(live.faceLayout, isNull);
      expect(live.toJson().containsKey('face_layout'), isFalse);
      expect(ProtocolDefinition.starter(ProtocolPath.gradualFace).live, isNull);
    });

    test('copyWith changes one setting, can clear the face layout', () {
      const base = LiveProtocolConfig(
        faceLayout: NormalizedFaceLayout(
          faceBox: Box(0, 0, 1, 1),
          eyeRegion: Box(0.2, 0.2, 0.6, 0.2),
          mouthRegion: Box(0.2, 0.6, 0.6, 0.2),
        ),
      );
      final more = base.copyWith(maxTurns: 12, storeTranscript: true);
      expect(more.maxTurns, 12);
      expect(more.storeTranscript, isTrue);
      expect(more.faceLayout, isNotNull);
      expect(more.copyWith(clearFaceLayout: true).faceLayout, isNull);
    });

    test('a protocol ref and an assignment know it is live', () {
      final ref = ProtocolRef.maybeFromJson({
        'id': 7,
        'name': 'Live chat',
        'version': 1,
        'path': 'live_conversation',
        'definition': liveDefinition,
      })!;
      expect(ref.path, ProtocolPath.liveConversation);
      expect(ref.definition!.live!.maxTurns, 6);
      final a = Assignment.fromJson({
        'id': 3,
        'status': 'pending_topic',
        'protocol': {'id': 7, 'name': 'Live chat', 'path': 'live_conversation'},
      });
      expect(a.isLive, isTrue);
      expect(a.isInterest, isFalse);
    });
  });
}

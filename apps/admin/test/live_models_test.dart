import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/live/domain/live_models.dart';
import 'package:research_admin/features/protocols/application/live_settings_draft.dart';

import 'live_fixtures.dart';

void main() {
  group('LiveAvatarStatus', () {
    test('reads the three providers, estimates, budget and the note', () {
      final s = sampleLiveStatus();
      expect(s.reply.name, 'fake');
      expect(s.reply.configured, isTrue);
      expect(s.reply.synthetic, isTrue);
      expect(s.reply.model, isNull);
      expect(s.avatar.streaming, isFalse);
      expect(s.perTurnUnits, 0.012);
      expect(s.avatarPerMinuteUnits, 0);
      expect(s.budget.costCapUnits, 5);
      expect(s.budget.spentUnits, 1.25);
      expect(s.budget.remainingUnits, 3.75);
      expect(s.sendFreeText, isTrue);
      expect(s.openConversations, 2);
      expect(s.note, startsWith('Development providers are synthetic'));
    });

    test('model, effort and the address of a local speech server', () {
      final s = claudeLiveStatus();
      expect(s.reply.name, 'anthropic');
      expect(s.reply.model, 'claude-opus-5-5');
      expect(s.reply.effort, 'low');
      expect(s.reply.synthetic, isFalse);
      expect(s.speech.baseUrl, 'http://127.0.0.1:8200');
      expect(s.avatar.streaming, isTrue);
    });

    test('an empty answer takes defaults and never throws', () {
      final s = LiveAvatarStatus.fromJson(const {});
      expect(s.reply.name, '');
      expect(s.reply.configured, isFalse);
      expect(s.avatar.streaming, isNull);
      expect(s.budget.costCapUnits, 0);
      expect(s.openConversations, 0);
      expect(s.note, '');
    });
  });

  group('StaffConversation', () {
    test('without a kept transcript every turn has no text', () {
      final c = sampleConversation();
      expect(c.conversation.topic, 'trains');
      expect(c.conversation.inputMode, LiveInputMode.speech);
      expect(c.conversation.isClosed, isTrue);
      expect(c.conversation.endReason, 'participant_ended');
      expect(c.conversation.turnsUsed, 3);
      expect(c.textKept, isFalse);
      expect(c.turns, hasLength(5));
      expect(c.turns.every((t) => t.text == null), isTrue);
      expect(c.turns[1].isParticipant, isTrue);
      expect(c.turns[1].flags, ['speech', 'participant_on_topic']);
      expect(c.costUnits, 0.0361);
      expect(c.outcome.participantTurns, 2);
      expect(c.outcome.onTopicShare, 0.5);
      expect(c.outcome.redirects, 1);
      expect(c.outcome.note, contains('reply model'));
    });

    test('with a kept transcript the text is there', () {
      final c = sampleConversation(withText: true, distress: 1);
      expect(c.textKept, isTrue);
      expect(c.turns[1].text, 'I like steam trains');
      expect(c.turns[3].flags, contains('distress'));
      expect(c.outcome.distress, 1);
    });

    test('an open conversation has no end reason', () {
      final c = sampleConversation(open: true);
      expect(c.conversation.isOpen, isTrue);
      expect(c.conversation.endReason, isNull);
      expect(c.conversation.turnsLeft, 5);
    });

    test('an on-topic share of null stays null', () {
      final json = conversationJson();
      (json['outcome'] as Map<String, dynamic>)['on_topic_share'] = null;
      expect(StaffConversation.fromJson(json).outcome.onTopicShare, isNull);
    });
  });

  group('ConversationMonitor', () {
    test('reads the block of the live monitor', () {
      final m = sampleMonitor(distress: 2);
      expect(m.isOpen, isTrue);
      expect(m.inputMode, LiveInputMode.speech);
      expect(m.turnsUsed, 3);
      expect(m.distress, 2);
      expect(m.redirects, 1);
      expect(m.lastTurn!.role, 'avatar');
      expect(m.lastTurn!.flags, ['scripted_line', 'redirect_line']);
      expect(m.lastTurn!.tMs, 83500);
      expect(m.endReason, isNull);
    });

    test('no block, no last turn', () {
      expect(ConversationMonitor.maybeFromJson(null), isNull);
      final m = sampleMonitor(lastTurn: false, status: 'closed', endReason: 'turn_limit');
      expect(m.lastTurn, isNull);
      expect(m.isOpen, isFalse);
      expect(m.endReason, 'turn_limit');
    });
  });

  group('ConversationReportColumns', () {
    test('reads the four columns', () {
      final c = ConversationReportColumns.fromRow({
        'conversation_turns': 4,
        'conversation_on_topic_share': 0.75,
        'conversation_distress': 1,
        'conversation_end_reason': 'turn_limit',
      });
      expect(c.turns, 4);
      expect(c.onTopicShare, 0.75);
      expect(c.distress, 1);
      expect(c.endReason, 'turn_limit');
      expect(c.isEmpty, isFalse);
    });

    test('nulls stay null', () {
      final c = ConversationReportColumns.fromRow({
        'conversation_turns': null,
        'conversation_on_topic_share': null,
      });
      expect(c.turns, isNull);
      expect(c.onTopicShare, isNull);
      expect(c.distress, isNull);
      expect(c.endReason, isNull);
      expect(c.isEmpty, isTrue);
    });
  });

  group('wording', () {
    test('end reasons read as staff wording', () {
      expect(conversationEndReasonLabel(null), '-');
      expect(conversationEndReasonLabel('participant'), 'Participant asked to stop');
      expect(conversationEndReasonLabel('participant_ended'), 'Participant pressed End');
      expect(conversationEndReasonLabel('turn_limit'), 'Turn limit reached');
      expect(conversationEndReasonLabel('time_limit'), 'Time limit reached');
      expect(conversationEndReasonLabel('budget'), 'Budget used up');
      expect(conversationEndReasonLabel('session_ended'), 'Session ended');
      expect(conversationEndReasonLabel('something_new'), 'Something new');
    });

    test('every flag of the contract has a short label', () {
      for (final flag in [
        'typed', 'speech', 'sample_speech', 'participant_truncated',
        'participant_on_topic', 'participant_off_topic', 'distress',
        'scripted_line', 'opening', 'closing', 'redirect_line', 'fallback_line',
        'reply_shortened', 'participant_wants_to_stop', 'refusal',
        'provider_error', 'no_reply', 'contact_or_link',
        'clinical_or_research_words', 'empty_reply', 'turn_limit',
        'time_limit', 'budget',
      ]) {
        final label = conversationFlagLabel(flag);
        expect(label, isNotEmpty, reason: flag);
        expect(label, isNot(contains('_')), reason: flag);
      }
      expect(conversationFlagLabel('brand_new_flag'), 'Brand new flag');
      expect(conversationFlagNeedsAttention('distress'), isTrue);
      expect(conversationFlagNeedsAttention('typed'), isFalse);
    });
  });

  group('protocol live section (core model)', () {
    test('a live definition round-trips through JSON', () {
      const config = LiveProtocolConfig(
        maxTurns: 12,
        inputModes: [LiveInputMode.typed],
        storeTranscript: true,
        faceLayout: NormalizedFaceLayout(
          faceBox: Box(0.3, 0.1, 0.4, 0.8),
          eyeRegion: Box(0.3, 0.25, 0.4, 0.2),
          mouthRegion: Box(0.35, 0.55, 0.3, 0.2),
        ),
      );
      final def = ProtocolDefinition(
        path: ProtocolPath.liveConversation,
        live: config,
      );
      final json = def.toJson();
      expect(json['path'], 'live_conversation');
      expect(json.containsKey('gradual'), isFalse);
      expect((json['live'] as Map)['max_turns'], 12);
      final back = ProtocolDefinition.maybeFromJson(json)!;
      expect(back.path, ProtocolPath.liveConversation);
      expect(back.live!.storeTranscript, isTrue);
      expect(back.live!.faceLayout!.eyeRegion.y, 0.25);
    });
  });

  group('LiveSettingsDraft', () {
    test('starts from the documented defaults', () {
      final d = LiveSettingsDraft();
      expect(d.maxTurns, '8');
      expect(d.maxMinutes, '8');
      expect(d.maxReplyWords, '40');
      expect(d.maxParticipantChars, '400');
      expect(d.openingLine, LiveProtocolConfig.defaultOpeningLine);
      expect(d.avatarId, '');
      expect(d.voiceId, '');
      expect(d.typed, isTrue);
      expect(d.speech, isTrue);
      expect(d.storeTranscript, isFalse);
      expect(d.useFaceLayout, isFalse);
      expect(d.errors(), isEmpty);
      final built = d.build()!;
      expect(built.maxTurns, 8);
      expect(built.inputModes, [LiveInputMode.typed, LiveInputMode.speech]);
      expect(built.faceLayout, isNull);
      expect(built.toJson().containsKey('face_layout'), isFalse);
    });

    test('ranges match the contract', () {
      LiveSettingsDraft with_(void Function(LiveSettingsDraft) edit) {
        final d = LiveSettingsDraft();
        edit(d);
        return d;
      }

      for (final (text, ok) in [
        ('1', true), ('30', true), ('0', false), ('31', false),
        ('2.5', false), ('abc', false), ('', false),
      ]) {
        expect(with_((d) => d.maxTurns = text).errors().containsKey('max-turns'),
            !ok, reason: 'turns $text');
        expect(with_((d) => d.maxMinutes = text).errors().containsKey('max-minutes'),
            !ok, reason: 'minutes $text');
      }
      for (final (text, ok) in [('10', true), ('80', true), ('9', false), ('81', false)]) {
        expect(with_((d) => d.maxReplyWords = text).errors().containsKey('max-reply-words'),
            !ok, reason: 'words $text');
      }
      for (final (text, ok) in [('50', true), ('1000', true), ('49', false), ('1001', false)]) {
        expect(
          with_((d) => d.maxParticipantChars = text)
              .errors()
              .containsKey('max-participant-chars'),
          !ok,
          reason: 'chars $text',
        );
      }
      expect(with_((d) => d.maxTurns = '31').errors()['max-turns'],
          'Maximum turns must be a whole number from 1 to 30.');
    });

    test('a comma is accepted as the decimal sign', () {
      final d = LiveSettingsDraft()
        ..useFaceLayout = true
        ..boxes[FaceRegion.face] = ['0,3', '0,1', '0,4', '0,8'];
      expect(d.errors(), isEmpty);
      expect(d.build()!.faceLayout!.faceBox.x, 0.3);
    });

    test('lines are required, at most 400 characters, without links or e-mail', () {
      final d = LiveSettingsDraft()
        ..openingLine = '   '
        ..closingLine = 'Visit https://example.org now'
        ..redirectLine = 'Write to me@example.org'
        ..distressLine = 'x' * 401;
      final e = d.errors();
      expect(e['opening-line'], 'Opening line is required (max 400 characters).');
      expect(e['closing-line'], 'Closing line must not contain links or e-mail addresses.');
      expect(e['redirect-line'], 'Redirect line must not contain links or e-mail addresses.');
      expect(e['distress-line'], 'Distress line must be at most 400 characters.');
      expect((LiveSettingsDraft()..openingLine = 'x' * 400).errors(), isEmpty);
      expect(
        (LiveSettingsDraft()..openingLine = 'See www.example.org').errors().containsKey('opening-line'),
        isTrue,
      );
      // The placeholders are not links.
      expect((LiveSettingsDraft()..openingLine = 'Hi {{display_name}}, {{topic}}?').errors(), isEmpty);
    });

    test('avatar and voice ids are at most 120 characters', () {
      final d = LiveSettingsDraft()
        ..avatarId = 'a' * 121
        ..voiceId = 'v' * 120;
      expect(d.errors().keys, ['avatar-id']);
    });

    test('at least one input mode', () {
      final d = LiveSettingsDraft()
        ..typed = false
        ..speech = false;
      expect(d.errors()['input-modes'], 'Choose at least one input mode.');
      expect(d.build(), isNull);
      d.speech = true;
      expect(d.build()!.inputModes, [LiveInputMode.speech]);
    });

    test('the face layout is checked only when it is on', () {
      final d = LiveSettingsDraft();
      d.boxes[FaceRegion.eye] = ['x', '', '', ''];
      expect(d.errors(), isEmpty);
      d.useFaceLayout = true;
      expect(d.errors().keys, contains('face-eye-x'));
    });

    test('each fraction must be a number from 0 to 1', () {
      final d = LiveSettingsDraft()
        ..useFaceLayout = true
        ..boxes[FaceRegion.face] = ['-0.1', '0.1', '1.5', 'abc'];
      final e = d.errors();
      expect(e['face-face-x'], 'Face box x must be a fraction from 0 to 1.');
      expect(e['face-face-w'], 'Face box width must be a fraction from 0 to 1.');
      expect(e['face-face-h'], 'Face box height must be a fraction from 0 to 1.');
      expect(e.containsKey('face-face-y'), isFalse);
    });

    test('the eye region must lie above the mouth region', () {
      final d = LiveSettingsDraft()..useFaceLayout = true;
      expect(d.faceRuleBroken, isFalse);
      // The sample: eye bottom 0.45, mouth top 0.55.
      d.boxes[FaceRegion.eye] = ['0.3', '0.5', '0.4', '0.2'];
      expect(d.faceRuleBroken, isTrue);
      expect(d.errors()['face-rule'], LiveSettingsDraft.faceRuleMessage);
      // Touching edges are allowed, as on the server.
      d.boxes[FaceRegion.eye] = ['0.3', '0.35', '0.4', '0.2'];
      expect(d.faceRuleBroken, isFalse);
      expect(d.errors(), isEmpty);
    });

    test('builds the layout from the typed fractions', () {
      final d = LiveSettingsDraft()..useFaceLayout = true;
      final layout = d.build()!.faceLayout!;
      expect(layout.faceBox, kSampleFaceLayout.faceBox);
      expect(layout.eyeRegion, kSampleFaceLayout.eyeRegion);
      expect(layout.mouthRegion, kSampleFaceLayout.mouthRegion);
    });

    test('starts from a protocol that has settings and a layout', () {
      final d = LiveSettingsDraft(
        config: const LiveProtocolConfig(
          maxTurns: 5,
          avatarId: 'av-1',
          inputModes: [LiveInputMode.speech],
          storeTranscript: true,
          faceLayout: NormalizedFaceLayout(
            faceBox: Box(0.2, 0.1, 0.5, 0.8),
            eyeRegion: Box(0.25, 0.2, 0.4, 0.2),
            mouthRegion: Box(0.3, 0.6, 0.3, 0.15),
          ),
        ),
      );
      expect(d.maxTurns, '5');
      expect(d.avatarId, 'av-1');
      expect(d.typed, isFalse);
      expect(d.speech, isTrue);
      expect(d.storeTranscript, isTrue);
      expect(d.useFaceLayout, isTrue);
      expect(d.boxes[FaceRegion.mouth], ['0.3', '0.6', '0.3', '0.15']);
    });
  });
}

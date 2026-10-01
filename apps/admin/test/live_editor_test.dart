import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/live/presentation/face_layout_preview.dart';
import 'package:research_admin/features/protocols/application/live_settings_draft.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'live_fixtures.dart';

Finder key(String k) => find.byKey(Key(k), skipOffstage: false);

Future<void> reveal(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String k) async {
  await reveal(tester, k);
  await tester.tap(find.byKey(Key(k)));
  await tester.pumpAndSettle();
}

Future<void> typeInto(WidgetTester tester, String k, String text) async {
  await reveal(tester, k);
  await tester.enterText(find.byKey(Key(k)), text);
  await tester.pump();
}

String fieldText(WidgetTester tester, String k) => tester
    .widget<EditableText>(find.descendant(
      of: key(k),
      matching: find.byType(EditableText, skipOffstage: false),
    ))
    .controller
    .text;

bool fieldEnabled(WidgetTester tester, String k) =>
    tester.widget<TextFormField>(key(k)).enabled;

/// The painter behind the face layout preview.
FaceLayoutPainter painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(key('face-layout-canvas')).painter!
        as FaceLayoutPainter;

String bannerText(WidgetTester tester, String k) =>
    tester.widget<MessageBanner>(key(k)).message;

/// Opens the Protocols tab and starts a new live protocol.
Future<TestBed> newLiveProtocol(
  WidgetTester tester, {
  String role = 'researcher',
  double width = 1440,
  TestBed? bed,
}) async {
  useWindow(tester, width, width < 500 ? 3000 : 2400);
  bed ??= TestBed();
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Protocols');
  await tapKey(tester, 'new-protocol');
  await typeInto(tester, 'protocol-name', 'Talk about trains');
  await tapKey(tester, 'protocol-path');
  await tester.tap(find.text(ProtocolPath.liveConversation.label).last);
  await tester.pumpAndSettle();
  return bed;
}

/// Opens an existing protocol of the list.
Future<void> openProtocol(
  WidgetTester tester,
  TestBed bed,
  String id, {
  String role = 'researcher',
  double width = 1440,
}) async {
  useWindow(tester, width, width < 500 ? 3000 : 2400);
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Protocols');
  await tapKey(tester, 'open-protocol-$id');
}

const _defaults = {
  'live-max-turns': '8',
  'live-max-minutes': '8',
  'live-max-reply-words': '40',
  'live-max-participant-chars': '400',
};

const _liveFields = [
  'live-max-turns',
  'live-max-minutes',
  'live-max-reply-words',
  'live-max-participant-chars',
  'live-opening-line',
  'live-closing-line',
  'live-redirect-line',
  'live-distress-line',
  'live-avatar-id',
  'live-voice-id',
];

void main() {
  group('Protocol editor, live path', () {
    testWidgets('the live path is offered next to the other two', (tester) async {
      useWindow(tester, 1440, 2400);
      await openStudy(tester, TestBed(), role: 'researcher');
      await openTab(tester, 'Protocols');
      await tapKey(tester, 'new-protocol');
      await tapKey(tester, 'protocol-path');
      for (final p in ProtocolPath.values) {
        expect(find.text(p.label), findsWidgets, reason: p.wire);
      }
      expect(find.text(ProtocolPath.liveConversation.label), findsWidgets);
    });

    testWidgets('choosing it shows the live section with the documented defaults',
        (tester) async {
      await newLiveProtocol(tester);

      expect(key('live-section'), findsOneWidget);
      expect(key('stage-0-row'), findsNothing, reason: 'no stage table');
      expect(key('interaction-points'), findsNothing);
      expect(fieldText(tester, 'live-max-turns'), '8');
      expect(fieldText(tester, 'live-max-minutes'), '8');
      expect(fieldText(tester, 'live-max-reply-words'), '40');
      expect(fieldText(tester, 'live-max-participant-chars'), '400');
      expect(fieldText(tester, 'live-opening-line'), LiveProtocolConfig.defaultOpeningLine);
      expect(fieldText(tester, 'live-closing-line'), LiveProtocolConfig.defaultClosingLine);
      expect(fieldText(tester, 'live-redirect-line'), LiveProtocolConfig.defaultRedirectLine);
      expect(fieldText(tester, 'live-distress-line'), LiveProtocolConfig.defaultDistressLine);
      expect(fieldText(tester, 'live-avatar-id'), '');
      expect(fieldText(tester, 'live-voice-id'), '');
      expect(tester.widget<CheckboxListTile>(key('live-mode-typed')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(key('live-mode-speech')).value, isTrue);
      expect(tester.widget<SwitchListTile>(key('live-store-transcript')).value, isFalse);
      expect(tester.widget<SwitchListTile>(key('live-face-layout-switch')).value, isFalse);
      expect(key('face-layout-preview'), findsNothing);
    });

    testWidgets('the fields carry the ranges and the hints of the contract',
        (tester) async {
      await newLiveProtocol(tester);

      for (final label in [
        'Max turns (1-30)',
        'Max minutes (1-30)',
        'Max reply words (10-80)',
        'Max participant characters (50-1000)',
      ]) {
        expect(find.text(label, skipOffstage: false), findsOneWidget, reason: label);
      }
      expect(
        find.textContaining('{{display_name}} and {{topic}} are filled in',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('Links and e-mail addresses are not allowed',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(find.textContaining('future streaming avatar vendor', skipOffstage: false),
          findsOneWidget);
      expect(
        find.text('Keep a written transcript when the participant agrees',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Typed', skipOffstage: false), findsOneWidget);
      expect(find.text('Speech', skipOffstage: false), findsOneWidget);
      // A character counter under each line.
      expect(
        find.text('${LiveProtocolConfig.defaultOpeningLine.length} / 400',
            skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('saving the defaults sends the live section and nothing else of the other paths',
        (tester) async {
      final bed = await newLiveProtocol(tester);
      await tapKey(tester, 'save-draft');

      expect(bed.protocols.created, hasLength(1));
      final sent = bed.protocols.created.single;
      expect(sent.name, 'Talk about trains');
      final def = sent.definition;
      expect(def['path'], 'live_conversation');
      expect(def.containsKey('gradual'), isFalse);
      expect(def.containsKey('interest'), isFalse);
      expect(def['live'], const LiveProtocolConfig().toJson());
      expect((def['live'] as Map).containsKey('face_layout'), isFalse);
      expect(bannerText(tester, 'editor-notice'), 'Draft saved.');
      expect(statusOf(tester), 'Draft');
    });

    testWidgets('edited values reach the server and come back into the fields',
        (tester) async {
      final bed = await newLiveProtocol(tester);
      await typeInto(tester, 'live-max-turns', '12');
      await typeInto(tester, 'live-max-minutes', '15');
      await typeInto(tester, 'live-max-reply-words', '30');
      await typeInto(tester, 'live-max-participant-chars', '250');
      await typeInto(tester, 'live-opening-line', 'Hello {{display_name}}, tell me about {{topic}}!');
      await typeInto(tester, 'live-avatar-id', 'avatar-7');
      await typeInto(tester, 'live-voice-id', 'voice-3');
      await tapKey(tester, 'live-store-transcript');
      await tapKey(tester, 'live-mode-speech'); // typed only
      await tapKey(tester, 'save-draft');

      final live = bed.protocols.created.single.definition['live'] as Map;
      expect(live['max_turns'], 12);
      expect(live['max_minutes'], 15);
      expect(live['max_reply_words'], 30);
      expect(live['max_participant_chars'], 250);
      expect(live['opening_line'], 'Hello {{display_name}}, tell me about {{topic}}!');
      expect(live['avatar_id'], 'avatar-7');
      expect(live['voice_id'], 'voice-3');
      expect(live['store_transcript'], isTrue);
      expect(live['input_modes'], ['typed']);

      // The editor now shows what the server stored.
      expect(fieldText(tester, 'live-max-turns'), '12');
      expect(fieldText(tester, 'live-avatar-id'), 'avatar-7');
      expect(tester.widget<CheckboxListTile>(key('live-mode-speech')).value, isFalse);
      expect(tester.widget<SwitchListTile>(key('live-store-transcript')).value, isTrue);

      // A second save is an update of the same draft.
      await typeInto(tester, 'live-max-turns', '9');
      await tapKey(tester, 'save-draft');
      expect(bed.protocols.created, hasLength(1));
      final update = bed.protocols.updated.single;
      expect((update.definition!['live'] as Map)['max_turns'], 9);
    });

    group('checks next to the fields', () {
      testWidgets('numbers outside the server ranges are marked and block Save',
          (tester) async {
        final bed = await newLiveProtocol(tester);

        for (final (field, text, message) in [
          ('live-max-turns', '31', 'Maximum turns must be a whole number from 1 to 30.'),
          ('live-max-turns', '0', 'Maximum turns must be a whole number from 1 to 30.'),
          ('live-max-minutes', '31', 'Maximum minutes must be a whole number from 1 to 30.'),
          ('live-max-reply-words', '9',
              'Maximum reply words must be a whole number from 10 to 80.'),
          ('live-max-reply-words', '81',
              'Maximum reply words must be a whole number from 10 to 80.'),
          ('live-max-participant-chars', '49',
              'Maximum participant characters must be a whole number from 50 to 1000.'),
          ('live-max-participant-chars', '1001',
              'Maximum participant characters must be a whole number from 50 to 1000.'),
          ('live-max-turns', 'many', 'Maximum turns must be a whole number from 1 to 30.'),
          ('live-max-turns', '2.5', 'Maximum turns must be a whole number from 1 to 30.'),
        ]) {
          await typeInto(tester, field, text);
          expect(find.text(message, skipOffstage: false), findsOneWidget,
              reason: '$field = $text');
          await tapKey(tester, 'save-draft');
          expect(bannerText(tester, 'editor-error'), message, reason: '$field = $text');
          expect(bed.protocols.created, isEmpty, reason: 'nothing is sent');
          // Back to a valid value.
          await typeInto(tester, field, _defaults[field]!);
          expect(find.text(message, skipOffstage: false), findsNothing);
        }
      });

      testWidgets('the four lines are required, at most 400 characters and free of links and e-mail',
          (tester) async {
        final bed = await newLiveProtocol(tester);

        await typeInto(tester, 'live-opening-line', '');
        expect(find.text('Opening line is required (max 400 characters).',
            skipOffstage: false), findsOneWidget);
        await typeInto(tester, 'live-closing-line', 'See https://example.org/now');
        expect(find.text('Closing line must not contain links or e-mail addresses.',
            skipOffstage: false), findsOneWidget);
        await typeInto(tester, 'live-redirect-line', 'Mail me at someone@example.org');
        expect(find.text('Redirect line must not contain links or e-mail addresses.',
            skipOffstage: false), findsOneWidget);
        await typeInto(tester, 'live-distress-line', 'x' * 401);
        expect(find.text('Distress line must be at most 400 characters.',
            skipOffstage: false), findsOneWidget);
        expect(find.text('401 / 400', skipOffstage: false), findsOneWidget);

        await tapKey(tester, 'save-draft');
        expect(bannerText(tester, 'editor-error'),
            'Opening line is required (max 400 characters).');
        expect(bed.protocols.created, isEmpty);

        // Fixing them makes Save work again.
        await typeInto(tester, 'live-opening-line', 'Hi {{display_name}}!');
        await typeInto(tester, 'live-closing-line', 'Bye {{display_name}}.');
        await typeInto(tester, 'live-redirect-line', 'Back to {{topic}}.');
        await typeInto(tester, 'live-distress-line', 'We can stop any time.');
        await tapKey(tester, 'save-draft');
        expect(bed.protocols.created, hasLength(1));
      });

      testWidgets('an avatar id longer than 120 characters is marked', (tester) async {
        await newLiveProtocol(tester);
        await typeInto(tester, 'live-avatar-id', 'a' * 121);
        expect(find.text('Avatar id must be at most 120 characters.', skipOffstage: false),
            findsOneWidget);
        await typeInto(tester, 'live-voice-id', 'v' * 121);
        expect(find.text('Voice id must be at most 120 characters.', skipOffstage: false),
            findsOneWidget);
      });

      testWidgets('at least one input mode must stay chosen', (tester) async {
        final bed = await newLiveProtocol(tester);
        await tapKey(tester, 'live-mode-typed');
        await tapKey(tester, 'live-mode-speech');
        expect(key('live-modes-error'), findsOneWidget);
        expect(tester.widget<Text>(key('live-modes-error')).data,
            'Choose at least one input mode.');
        await tapKey(tester, 'save-draft');
        expect(bannerText(tester, 'editor-error'), 'Choose at least one input mode.');
        expect(bed.protocols.created, isEmpty);

        await tapKey(tester, 'live-mode-speech');
        expect(key('live-modes-error'), findsNothing);
        await tapKey(tester, 'save-draft');
        expect((bed.protocols.created.single.definition['live'] as Map)['input_modes'],
            ['speech']);
      });
    });

    group('face layout', () {
      testWidgets('is off by default and optional', (tester) async {
        final bed = await newLiveProtocol(tester);
        expect(key('face-layout-preview'), findsNothing);
        expect(key('live-face-eye-x'), findsNothing);
        await tapKey(tester, 'save-draft');
        expect((bed.protocols.created.single.definition['live'] as Map)
            .containsKey('face_layout'), isFalse);
      });

      testWidgets('switching it on shows twelve fractions and a preview of the three boxes',
          (tester) async {
        await newLiveProtocol(tester);
        await tapKey(tester, 'live-face-layout-switch');

        expect(key('face-layout-preview'), findsOneWidget);
        for (final region in ['face', 'eye', 'mouth']) {
          for (final axis in ['x', 'y', 'w', 'h']) {
            expect(key('live-face-$region-$axis'), findsOneWidget, reason: '$region $axis');
          }
        }
        expect(find.text('Face box', skipOffstage: false), findsOneWidget);
        expect(find.text('Eye region', skipOffstage: false), findsOneWidget);
        expect(find.text('Mouth region', skipOffstage: false), findsOneWidget);
        expect(fieldText(tester, 'live-face-face-x'), '0.3');
        expect(fieldText(tester, 'live-face-eye-y'), '0.25');
        expect(fieldText(tester, 'live-face-mouth-w'), '0.3');

        final p = painter(tester);
        expect(p.face, const Box(0.3, 0.1, 0.4, 0.8));
        expect(p.eye, const Box(0.3, 0.25, 0.4, 0.2));
        expect(p.mouth, const Box(0.35, 0.55, 0.3, 0.2));
        expect(p.eyeColor, FaceLayoutPreview.eyeColor);
        expect(tester.widget<Text>(key('face-layout-rule')).data,
            'The eye region must lie above the mouth region.');
      });

      testWidgets('the preview follows what is typed', (tester) async {
        await newLiveProtocol(tester);
        await tapKey(tester, 'live-face-layout-switch');

        await typeInto(tester, 'live-face-mouth-y', '0.7');
        await typeInto(tester, 'live-face-eye-h', '0.3');
        expect(painter(tester).mouth, const Box(0.35, 0.7, 0.3, 0.2));
        expect(painter(tester).eye, const Box(0.3, 0.25, 0.4, 0.3));

        // A box that is not complete yet is left out of the picture.
        await typeInto(tester, 'live-face-face-w', '');
        expect(painter(tester).face, isNull);
        expect(painter(tester).eye, isNotNull);
      });

      testWidgets('an eye region that is not above the mouth region is flagged and blocks Save',
          (tester) async {
        final bed = await newLiveProtocol(tester);
        await tapKey(tester, 'live-face-layout-switch');
        await typeInto(tester, 'live-face-eye-y', '0.5'); // bottom 0.7 > mouth top 0.55

        expect(tester.widget<Text>(key('face-layout-rule')).data,
            LiveSettingsDraft.faceRuleMessage);
        expect(painter(tester).eyeColor, AppColors.error);
        expect(painter(tester).mouthColor, AppColors.error);

        await tapKey(tester, 'save-draft');
        expect(bannerText(tester, 'editor-error'), LiveSettingsDraft.faceRuleMessage);
        expect(bed.protocols.created, isEmpty);

        // Touching edges are fine: eye bottom 0.55 = mouth top 0.55.
        await typeInto(tester, 'live-face-eye-y', '0.35');
        expect(tester.widget<Text>(key('face-layout-rule')).data,
            'The eye region must lie above the mouth region.');
        expect(painter(tester).eyeColor, FaceLayoutPreview.eyeColor);
        await tapKey(tester, 'save-draft');
        expect(bed.protocols.created, hasLength(1));
      });

      testWidgets('a fraction outside 0 to 1 is marked and explained', (tester) async {
        final bed = await newLiveProtocol(tester);
        await tapKey(tester, 'live-face-layout-switch');
        await typeInto(tester, 'live-face-face-w', '1.5');
        expect(find.text('Face box width must be a fraction from 0 to 1.',
            skipOffstage: false), findsOneWidget);
        await typeInto(tester, 'live-face-mouth-x', 'left');
        expect(find.text('Mouth region x must be a fraction from 0 to 1.',
            skipOffstage: false), findsOneWidget);
        await tapKey(tester, 'save-draft');
        expect(bed.protocols.created, isEmpty);
        expect(key('editor-error'), findsOneWidget);
      });

      testWidgets('a valid layout is sent as three boxes of four fractions',
          (tester) async {
        final bed = await newLiveProtocol(tester);
        await tapKey(tester, 'live-face-layout-switch');
        await typeInto(tester, 'live-face-face-x', '0.25');
        await tapKey(tester, 'save-draft');

        final live = bed.protocols.created.single.definition['live'] as Map;
        expect(live['face_layout'], {
          'face_box': [0.25, 0.1, 0.4, 0.8],
          'eye_region': [0.3, 0.25, 0.4, 0.2],
          'mouth_region': [0.35, 0.55, 0.3, 0.2],
        });
        // After the save the layout is still on.
        expect(key('face-layout-preview'), findsOneWidget);
        expect(painter(tester).face, const Box(0.25, 0.1, 0.4, 0.8));
      });

      testWidgets('switching it off again sends no layout', (tester) async {
        final bed = await newLiveProtocol(tester);
        await tapKey(tester, 'live-face-layout-switch');
        await tapKey(tester, 'live-face-layout-switch');
        expect(key('face-layout-preview'), findsNothing);
        await tapKey(tester, 'save-draft');
        expect((bed.protocols.created.single.definition['live'] as Map)
            .containsKey('face_layout'), isFalse);
      });
    });

    testWidgets("the server's 422 text is shown as written", (tester) async {
      final bed = await newLiveProtocol(tester);
      bed.protocols.writeFailure = const ApiException(
        'live.face_layout.eye_region must lie above mouth_region',
        statusCode: 422,
      );
      await tapKey(tester, 'save-draft');
      expect(bannerText(tester, 'editor-error'),
          'live.face_layout.eye_region must lie above mouth_region');
      // Nothing was lost.
      expect(fieldText(tester, 'live-max-turns'), '8');
    });

    testWidgets('publishing saves the live draft first and then freezes it',
        (tester) async {
      final bed = await newLiveProtocol(tester);
      await typeInto(tester, 'live-max-turns', '10');
      await tapKey(tester, 'publish');
      await tester.tap(find.byKey(const Key('publish-confirm')));
      await tester.pumpAndSettle();

      expect((bed.protocols.created.single.definition['live'] as Map)['max_turns'], 10);
      expect(bed.protocols.published, hasLength(1));
      expect(statusOf(tester), 'Published, version 1');
      // Now read-only.
      expect(fieldEnabled(tester, 'live-max-turns'), isFalse);
    });

    group('existing protocols', () {
      final custom = LiveProtocolConfig(
        maxTurns: 5,
        maxMinutes: 3,
        maxReplyWords: 25,
        maxParticipantChars: 120,
        openingLine: 'Welcome {{display_name}}.',
        avatarId: 'av-1',
        voiceId: 'vo-1',
        inputModes: const [LiveInputMode.speech],
        storeTranscript: true,
        faceLayout: const NormalizedFaceLayout(
          faceBox: Box(0.2, 0.1, 0.5, 0.8),
          eyeRegion: Box(0.25, 0.2, 0.4, 0.2),
          mouthRegion: Box(0.3, 0.6, 0.3, 0.15),
        ),
      );

      testWidgets('a draft shows its stored settings, layout included', (tester) async {
        final bed = TestBed(
          protocols: FakeProtocolsRepository(items: [
            liveProtocol('7', 'Trains live', config: custom),
          ]),
        );
        await openProtocol(tester, bed, '7');

        expect(fieldText(tester, 'live-max-turns'), '5');
        expect(fieldText(tester, 'live-max-minutes'), '3');
        expect(fieldText(tester, 'live-max-reply-words'), '25');
        expect(fieldText(tester, 'live-max-participant-chars'), '120');
        expect(fieldText(tester, 'live-opening-line'), 'Welcome {{display_name}}.');
        expect(fieldText(tester, 'live-avatar-id'), 'av-1');
        expect(fieldText(tester, 'live-voice-id'), 'vo-1');
        expect(tester.widget<CheckboxListTile>(key('live-mode-typed')).value, isFalse);
        expect(tester.widget<CheckboxListTile>(key('live-mode-speech')).value, isTrue);
        expect(tester.widget<SwitchListTile>(key('live-store-transcript')).value, isTrue);
        expect(tester.widget<SwitchListTile>(key('live-face-layout-switch')).value, isTrue);
        expect(painter(tester).mouth, const Box(0.3, 0.6, 0.3, 0.15));
        expect(fieldText(tester, 'live-face-eye-w'), '0.4');
        expect(statusOf(tester), 'Draft');

        // Saving without a change sends the same section back.
        await typeInto(tester, 'live-max-turns', '6');
        await tapKey(tester, 'save-draft');
        final live = bed.protocols.updated.single.definition!['live'] as Map;
        expect(live['max_turns'], 6);
        expect(live['face_layout'], isNotNull);
        expect(live['input_modes'], ['speech']);
      });

      testWidgets('a published version is read-only, like the other paths',
          (tester) async {
        final bed = TestBed(
          protocols: FakeProtocolsRepository(items: [
            liveProtocol('8', 'Trains live v1',
                version: 1, status: ProtocolStatus.published, config: custom),
          ]),
        );
        await openProtocol(tester, bed, '8');

        expect(statusOf(tester), 'Published, version 1');
        expect(key('published-note'), findsOneWidget);
        for (final field in _liveFields) {
          expect(fieldEnabled(tester, field), isFalse, reason: field);
        }
        for (final box in ['face', 'eye', 'mouth']) {
          for (final axis in ['x', 'y', 'w', 'h']) {
            expect(fieldEnabled(tester, 'live-face-$box-$axis'), isFalse);
          }
        }
        for (final k in ['live-mode-typed', 'live-mode-speech']) {
          expect(tester.widget<CheckboxListTile>(key(k)).onChanged, isNull, reason: k);
        }
        for (final k in ['live-store-transcript', 'live-face-layout-switch']) {
          expect(tester.widget<SwitchListTile>(key(k)).onChanged, isNull, reason: k);
        }
        expect(key('save-draft'), findsNothing);
        expect(key('publish'), findsNothing);
        expect(key('new-draft'), findsOneWidget);
        // The values are all there to read.
        expect(fieldText(tester, 'live-max-turns'), '5');
        expect(painter(tester).face, const Box(0.2, 0.1, 0.5, 0.8));
      });

      testWidgets('New draft from published keeps the live settings and makes them editable',
          (tester) async {
        final bed = TestBed(
          protocols: FakeProtocolsRepository(items: [
            liveProtocol('8', 'Trains live v1',
                version: 1, status: ProtocolStatus.published, config: custom),
          ]),
        );
        await openProtocol(tester, bed, '8');
        await tapKey(tester, 'new-draft');

        expect(bed.protocols.newDrafts, ['8']);
        expect(statusOf(tester), 'Draft');
        expect(fieldEnabled(tester, 'live-max-turns'), isTrue);
        expect(fieldText(tester, 'live-max-turns'), '5');
        expect(fieldText(tester, 'live-avatar-id'), 'av-1');
        expect(key('save-draft'), findsOneWidget);
      });

      testWidgets('analysts see the live settings but cannot change them',
          (tester) async {
        final bed = TestBed(
          protocols: FakeProtocolsRepository(items: [
            liveProtocol('7', 'Trains live', config: custom),
          ]),
        );
        await openProtocol(tester, bed, '7', role: 'analyst');

        expect(find.textContaining('read-only access'), findsOneWidget);
        expect(fieldText(tester, 'live-max-turns'), '5');
        for (final field in _liveFields) {
          expect(fieldEnabled(tester, field), isFalse, reason: field);
        }
        expect(tester.widget<SwitchListTile>(key('live-store-transcript')).onChanged, isNull);
        expect(key('save-draft'), findsNothing);
        expect(key('publish'), findsNothing);
        expect(key('new-draft'), findsNothing);
      });
    });

    testWidgets('the list names the path', (tester) async {
      useWindow(tester, 1440, 900);
      final bed = TestBed(
        protocols: FakeProtocolsRepository(items: [
          liveProtocol('7', 'Trains live'),
        ]),
      );
      await openStudy(tester, bed);
      await openTab(tester, 'Protocols');
      expect(find.descendant(
        of: find.byKey(const Key('protocols-table')),
        matching: find.text('Live conversation with an avatar'),
      ), findsOneWidget);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the live section with a face layout fits ${width.toInt()} px',
          (tester) async {
        await newLiveProtocol(tester, width: width);
        await tapKey(tester, 'live-face-layout-switch');
        // Show a few errors as well: they take more room.
        await typeInto(tester, 'live-max-turns', '99');
        await typeInto(tester, 'live-opening-line', '');
        await typeInto(tester, 'live-face-eye-y', '0.9');
        await typeInto(tester, 'live-face-face-w', '2');
        expect(tester.takeException(), isNull);
        expect(key('live-section'), findsOneWidget);
        expect(key('face-layout-preview'), findsOneWidget);
        final size = tester.getSize(find.byKey(const Key('face-layout-canvas')));
        expect(size.width, lessThanOrEqualTo(width));
      });
    }
  });
}

String statusOf(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
      of: key('protocol-status'),
      matching: find.byType(Text, skipOffstage: false),
      skipOffstage: false,
    ))
    .data!;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openProtocols(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Protocols');
}

/// The form is built in full, but what is scrolled out of view counts as
/// offstage for finders: scroll to it first.
Future<void> reveal(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key), skipOffstage: false));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await reveal(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await reveal(tester, key);
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

/// Picks [label] in the dropdown with [key].
Future<void> choose(WidgetTester tester, String key, String label) async {
  await tapKey(tester, key);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The label of the status chip of the open editor.
String statusText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
      of: find.byKey(const Key('protocol-status'), skipOffstage: false),
      matching: find.byType(Text, skipOffstage: false),
      skipOffstage: false,
    ))
    .data!;

String fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    ))
    .controller
    .text;

void main() {
  group('Protocols tab', () {
    testWidgets('lists protocols with version, status and path', (tester) async {
      useWindow(tester, 1440, 900);
      await openProtocols(tester, TestBed());

      final table = find.byKey(const Key('protocols-table'));
      expect(table, findsOneWidget);
      for (final header in ['Name', 'Version', 'Status', 'Path', 'Created']) {
        expect(find.descendant(of: table, matching: find.text(header)), findsOneWidget);
      }
      expect(find.descendant(of: table, matching: find.text('Published')), findsWidgets);
      expect(find.text('Faces v1'), findsOneWidget);
      expect(find.text('Faces v2 draft'), findsOneWidget);
      expect(find.text('Trains talk'), findsOneWidget);
      expect(find.text('Published'), findsWidgets);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Gradual face practice'), findsNWidgets(2));
      expect(find.text('Interest conversation'), findsOneWidget);
      expect(find.text('2026-09-30 09:00 UTC'), findsNWidgets(2));
      // A draft is edited, a published version viewed or copied.
      expect(find.byKey(const Key('open-protocol-2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('open-protocol-2')), matching: find.text('Edit')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('open-protocol-1')), matching: find.text('View')),
          findsOneWidget);
      expect(find.byKey(const Key('new-draft-1')), findsOneWidget);
      expect(find.byKey(const Key('new-draft-2')), findsNothing);
      expect(find.byKey(const Key('new-protocol')), findsOneWidget);
    });

    testWidgets('analysts can look but not change', (tester) async {
      useWindow(tester, 1440, 900);
      await openProtocols(tester, TestBed(), role: 'analyst');
      expect(find.byKey(const Key('protocols-table')), findsOneWidget);
      expect(find.byKey(const Key('new-protocol')), findsNothing);
      expect(find.byKey(const Key('new-draft-1')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('open-protocol-2')), matching: find.text('View')),
          findsOneWidget);
    });

    testWidgets('an empty study says so', (tester) async {
      useWindow(tester, 800, 900);
      await openProtocols(tester, TestBed(protocols: FakeProtocolsRepository(items: [])));
      expect(find.byKey(const Key('no-protocols')), findsOneWidget);
    });

    testWidgets('New draft copies a published version and opens the editor',
        (tester) async {
      useWindow(tester, 1440, 900);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tapVisible(tester, find.byKey(const Key('new-draft-1')));
      expect(bed.protocols.newDrafts, ['1']);
      expect(find.byKey(const Key('protocol-status'), skipOffstage: false), findsOneWidget);
      expect(statusText(tester), 'Draft');
      expect(fieldText(tester, 'protocol-name'), 'Faces v1');
      expect(find.byKey(const Key('save-draft'), skipOffstage: false), findsOneWidget);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the tab and the editor fit ${width.toInt()} px', (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        await openProtocols(tester, TestBed());
        expect(find.byKey(const Key('protocols-table')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tapKey(tester, 'open-protocol-2');
        expect(find.byKey(const Key('protocol-name'), skipOffstage: false), findsOneWidget);
        // Walk down the whole form: nothing may overflow.
        for (final key in ['baseline-seconds', 'label-5', 'hold-invalid',
            'stage-0-row', 'stage-1-seconds', 'real-face-url', 'save-draft']) {
          await reveal(tester, key);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('protocol editor', () {
    testWidgets('a new protocol: fill it in, add a stage, save the draft',
        (tester) async {
      useWindow(tester, 1000, 1600);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tester.tap(find.byKey(const Key('new-protocol')));
      await tester.pumpAndSettle();

      expect(statusText(tester), 'Draft, not saved yet');
      // Starter values.
      expect(fieldText(tester, 'baseline-seconds'), '30');
      expect(fieldText(tester, 'label-1'), 'Very uncomfortable');
      expect(find.byKey(const Key('stage-0-row'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('stage-1-row'), skipOffstage: false), findsOneWidget);

      await typeInto(tester, 'protocol-name', 'Slow faces');
      await typeInto(tester, 'baseline-seconds', '45');
      await typeInto(tester, 'post-seconds', '40');
      await typeInto(tester, 'stage-0-trials', '5');
      await typeInto(tester, 'stage-0-min-correct', '0.75');
      await typeInto(tester, 'stage-0-seconds', '6.5');
      await choose(tester, 'stage-0-mode', 'Four choices');
      await choose(tester, 'stage-1-level', '1 · Face-like shape');
      // Add a stage: it copies the last one.
      await tapKey(tester, 'add-stage');
      expect(find.byKey(const Key('stage-2-row'), skipOffstage: false), findsOneWidget);
      await choose(tester, 'stage-2-zone', 'Near the eyes');
      await choose(tester, 'final-zone-limit', 'Eye region');
      await tapKey(tester, 'allow-simultaneous');
      await tester.pump();
      await typeInto(tester, 'real-face-url', 'https://media.test/face.png');

      await tapKey(tester, 'save-draft');

      expect(bed.protocols.created, hasLength(1));
      final saved = bed.protocols.created.single;
      expect(saved.name, 'Slow faces');
      final def = saved.definition;
      expect(def['path'], 'gradual_face');
      expect(def['baseline_seconds'], 45);
      expect(def['post_seconds'], 40);
      final gradual = def['gradual'] as Map<String, dynamic>;
      final stages = gradual['stages'] as List;
      expect(stages, hasLength(3));
      expect(stages[0], {
        'face_level': 0,
        'number_zone': 'outside',
        'trials': 5,
        'min_correct': 0.75,
        'response_mode': 'four_choice',
        'trial_seconds': 6.5,
      });
      expect((stages[1] as Map)['face_level'], 1);
      expect((stages[2] as Map)['number_zone'], 'near_eyes');
      expect(gradual['final_zone_limit'], 'eye_region');
      expect(gradual['allow_simultaneous_change'], true);
      expect(gradual['real_face_media_url'], 'https://media.test/face.png');
      expect(find.text('Draft saved.'), findsOneWidget);
      expect(statusText(tester), 'Draft');
    });

    testWidgets('a stage can be removed but the last one stays', (tester) async {
      useWindow(tester, 1000, 1600);
      await openProtocols(tester, TestBed());
      await tapKey(tester, 'open-protocol-2');
      expect(find.byKey(const Key('stage-1-row'), skipOffstage: false), findsOneWidget);
      await tapKey(tester, 'stage-1-remove');
      expect(find.byKey(const Key('stage-1-row'), skipOffstage: false), findsNothing);
      final last = tester.widget<IconButton>(find.byKey(const Key('stage-0-remove'), skipOffstage: false));
      expect(last.onPressed, isNull);
    });

    testWidgets('the comfort scale follows the number of values', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tapKey(tester, 'open-protocol-2');

      await choose(tester, 'scale-max', '4');
      expect(find.byKey(const Key('label-4'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('label-5'), skipOffstage: false), findsNothing);
      await typeInto(tester, 'label-4', 'Great');
      await tapKey(tester, 'save-draft');
      final comfort = bed.protocols.updated.single.definition!['comfort'] as Map;
      expect(comfort['scale_max'], 4);
      expect((comfort['labels'] as List).last, 'Great');
      expect(comfort['labels'], hasLength(4));
      expect(comfort['min_ok'], 3);
    });

    testWidgets('the interest path has interaction points and no stage table',
        (tester) async {
      useWindow(tester, 1000, 1600);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tester.tap(find.byKey(const Key('new-protocol')));
      await tester.pumpAndSettle();
      await choose(tester, 'protocol-path', 'Interest conversation');
      expect(find.byKey(const Key('interaction-points'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('add-stage'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('stage-0-row'), skipOffstage: false), findsNothing);

      await typeInto(tester, 'protocol-name', 'Talk');
      await typeInto(tester, 'interaction-points', '3');
      await tapKey(tester, 'save-draft');
      final def = bed.protocols.created.single.definition;
      expect(def['path'], 'interest_conversation');
      expect(def['interest'], {'interaction_points': 3});
      expect(def.containsKey('gradual'), isFalse);
    });

    testWidgets('a server 422 is shown word for word', (tester) async {
      useWindow(tester, 1000, 1600);
      const message = 'gradual.stages[1] changes both face_level and '
          'number_zone; allow_simultaneous_change is off';
      final bed = TestBed(protocols: FakeProtocolsRepository()
        ..writeFailure = const ApiException(message, statusCode: 422));
      await openProtocols(tester, bed);
      await tapKey(tester, 'open-protocol-2');

      await tapKey(tester, 'save-draft');
      expect(find.byKey(const Key('editor-error')), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      // Nothing was stored and the form is still editable.
      expect(bed.protocols.updated, isEmpty);
      expect(find.byKey(const Key('save-draft'), skipOffstage: false), findsOneWidget);

      // The same for publish.
      await tapKey(tester, 'publish');
      await tester.tap(find.byKey(const Key('publish-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(bed.protocols.published, isEmpty);
    });

    testWidgets('a number that is not a number is reported before saving',
        (tester) async {
      useWindow(tester, 1000, 1600);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tapKey(tester, 'open-protocol-2');
      await typeInto(tester, 'baseline-seconds', 'abc');
      await tapKey(tester, 'save-draft');
      expect(find.text('Baseline seconds must be a number.'), findsOneWidget);
      expect(bed.protocols.updated, isEmpty);

      await typeInto(tester, 'baseline-seconds', '30');
      await typeInto(tester, 'stage-1-trials', '2.5');
      await tapKey(tester, 'save-draft');
      expect(find.text('Stage 2 trials must be a whole number.'), findsOneWidget);
    });

    testWidgets('a protocol needs a name', (tester) async {
      useWindow(tester, 1000, 1600);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tester.tap(find.byKey(const Key('new-protocol')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'save-draft');
      expect(find.text('Give the protocol a name.'), findsOneWidget);
      expect(bed.protocols.created, isEmpty);
    });

    testWidgets('Publish asks first: published versions cannot be edited',
        (tester) async {
      useWindow(tester, 1000, 1600);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tapKey(tester, 'open-protocol-2');
      await typeInto(tester, 'protocol-name', 'Faces v2 final');

      await tapKey(tester, 'publish');
      expect(find.byKey(const Key('publish-dialog')), findsOneWidget);
      expect(find.textContaining('Published versions cannot be edited'), findsOneWidget);

      // Cancel: nothing happens.
      await tester.tap(find.byKey(const Key('publish-cancel')));
      await tester.pumpAndSettle();
      expect(bed.protocols.published, isEmpty);
      expect(bed.protocols.updated, isEmpty);

      // Confirm: the typed changes are saved, then the draft is published.
      await tester.tap(find.byKey(const Key('publish'), skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('publish-confirm')));
      await tester.pumpAndSettle();
      expect(bed.protocols.updated.single.name, 'Faces v2 final');
      expect(bed.protocols.published, ['2']);
      expect(statusText(tester), 'Published, version 1');
      // Now read-only: no save or publish, fields are disabled.
      expect(find.byKey(const Key('save-draft'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('publish'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('published-note'), skipOffstage: false), findsOneWidget);
      final name = tester.widget<TextFormField>(find.byKey(const Key('protocol-name'), skipOffstage: false));
      expect(name.enabled, isFalse);
      expect(find.byKey(const Key('add-stage'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('new-draft'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('New draft from published replaces the read-only view with a copy',
        (tester) async {
      useWindow(tester, 1000, 1600);
      final bed = TestBed();
      await openProtocols(tester, bed);
      await tapKey(tester, 'open-protocol-1');
      expect(find.byKey(const Key('published-note'), skipOffstage: false), findsOneWidget);
      expect(statusText(tester), 'Published, version 1');

      await tapKey(tester, 'new-draft');
      expect(bed.protocols.newDrafts, ['1']);
      expect(find.byKey(const Key('published-note'), skipOffstage: false), findsNothing);
      expect(statusText(tester), 'Draft');
      expect(find.byKey(const Key('save-draft'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('publish'), skipOffstage: false), findsOneWidget);
      expect(find.text('A new draft was created from the published version.'),
          findsOneWidget);
    });

    testWidgets('analysts see a protocol read-only', (tester) async {
      useWindow(tester, 1000, 1600);
      await openProtocols(tester, TestBed(), role: 'analyst');
      await tapKey(tester, 'open-protocol-2');
      expect(find.byKey(const Key('save-draft'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('publish'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('add-stage'), skipOffstage: false), findsNothing);
      final name = tester.widget<TextFormField>(find.byKey(const Key('protocol-name'), skipOffstage: false));
      expect(name.enabled, isFalse);
      expect(find.textContaining('read-only access'), findsOneWidget);
    });

    testWidgets('the editor shows what the server sent for a stage', (tester) async {
      useWindow(tester, 1000, 1600);
      final repo = FakeProtocolsRepository(items: [
        ProtocolDetail(
          summary: protocolRow('9', 'Custom'),
          definition: const ProtocolDefinition(
            path: ProtocolPath.gradualFace,
            baselineSeconds: 20,
            postSeconds: 25,
            comfort: ComfortConfig(scaleMax: 3, labels: ['Bad', 'Ok', 'Good'], minOk: 2),
            gradual: GradualConfig(
              stages: [
                GradualStage(
                  faceLevel: 3,
                  numberZone: NumberZone.eyeRegion,
                  trials: 7,
                  minCorrect: 0.9,
                  responseMode: StageResponseMode.symbol,
                  trialSeconds: 5,
                ),
              ],
              finalZoneLimit: NumberZone.eyeRegion,
              allowSimultaneousChange: true,
              realFaceMediaUrl: 'https://media.test/f.png',
            ),
          ),
        ),
      ]);
      await openProtocols(tester, TestBed(protocols: repo));
      await tapKey(tester, 'open-protocol-9');
      expect(fieldText(tester, 'baseline-seconds'), '20');
      expect(fieldText(tester, 'post-seconds'), '25');
      expect(fieldText(tester, 'label-3'), 'Good');
      expect(find.byKey(const Key('label-4'), skipOffstage: false), findsNothing);
      expect(fieldText(tester, 'stage-0-trials'), '7');
      expect(fieldText(tester, 'stage-0-min-correct'), '0.9');
      expect(fieldText(tester, 'stage-0-seconds'), '5');
      expect(find.text('3 · Real face'), findsOneWidget);
      expect(find.text('Symbols'), findsOneWidget);
      expect(fieldText(tester, 'real-face-url'), 'https://media.test/f.png');
    });
  });
}

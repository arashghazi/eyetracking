import 'dart:async';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/content/application/content_editor_controller.dart';
import 'package:research_admin/features/content/domain/media_picker.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openContent(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Content');
}

/// The form is built in full but what is scrolled away is offstage for
/// finders: scroll to it first.
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

String fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(find.descendant(
      of: find.byKey(Key(key), skipOffstage: false),
      matching: find.byType(EditableText, skipOffstage: false),
      skipOffstage: false,
    ))
    .controller
    .text;

Finder off(String key) => find.byKey(Key(key), skipOffstage: false);

void main() {
  group('Content tab', () {
    testWidgets('lists content with status and missing media', (tester) async {
      useWindow(tester, 1440, 900);
      await openContent(tester, TestBed());

      final table = find.byKey(const Key('content-table'));
      expect(table, findsOneWidget);
      for (final header in ['Title', 'Status', 'Topic tags', 'Face', 'Voice', 'Media']) {
        expect(find.descendant(of: table, matching: find.text(header)), findsOneWidget);
      }
      expect(find.text('Trains, part one'), findsOneWidget);
      expect(find.text('trains, railways'), findsOneWidget);
      expect(find.text('Approved'), findsNWidgets(2));
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Missing: s2.webm'), findsOneWidget);
      expect(find.text('All uploaded'), findsNWidgets(2));
      expect(find.byKey(const Key('new-content')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('open-content-2')), matching: find.text('Edit')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('open-content-1')), matching: find.text('View')),
          findsOneWidget);
    });

    testWidgets('analysts cannot create', (tester) async {
      useWindow(tester, 1440, 900);
      await openContent(tester, TestBed(), role: 'analyst');
      expect(find.byKey(const Key('content-table')), findsOneWidget);
      expect(find.byKey(const Key('new-content')), findsNothing);
    });

    testWidgets('an empty study says so', (tester) async {
      useWindow(tester, 800, 900);
      await openContent(tester, TestBed(content: FakeContentRepository(items: [])));
      expect(find.byKey(const Key('no-content')), findsOneWidget);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the tab and the editor fit ${width.toInt()} px', (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        await openContent(tester, TestBed());
        expect(tester.takeException(), isNull);
        final open = find.byKey(const Key('open-content-2'));
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        await tester.tap(open);
        await tester.pumpAndSettle();
        for (final key in [
          'content-title', 'tag-field', 'segment-0-row', 'segment-1-face',
          'start-segment', 'comprehension-0-row', 'upload-s2.webm', 'save-content',
        ]) {
          await reveal(tester, key);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('parsing Option=segment lines', () {
    test('options, branches and bare options', () {
      final p = parseOptionLines('Trains=s2\n  Planes = s2b \nNeither\n\n=s9\nBoats=');
      expect(p.options, ['Trains', 'Planes', 'Neither', 'Boats']);
      expect(p.branches, {'Trains': 's2', 'Planes': 's2b'});
    });

    test('lines are written back the same way', () {
      expect(
        optionLines(['Trains', 'Planes', 'Neither'], {'Trains': 's2', 'Planes': 's2b'}),
        'Trains=s2\nPlanes=s2b\nNeither',
      );
    });
  });

  group('content editor', () {
    testWidgets('an existing draft shows its segments, question lines and layout',
        (tester) async {
      useWindow(tester, 1000, 1400);
      await openContent(tester, TestBed());
      await tapKey(tester, 'open-content-2');

      expect(fieldText(tester, 'content-title'), 'Planes, draft');
      expect(find.byKey(const Key('tag-planes'), skipOffstage: false), findsOneWidget);
      expect(fieldText(tester, 'face-id'), 'f2');
      expect(fieldText(tester, 'segment-0-id'), 's1');
      expect(fieldText(tester, 'segment-0-media'), 's1.webm');
      expect(fieldText(tester, 'segment-0-duration'), '20');
      expect(fieldText(tester, 'segment-0-question'), 'Which do you prefer?');
      expect(fieldText(tester, 'segment-0-options'), 'Trains=s2\nPlanes');
      expect(fieldText(tester, 'segment-0-face'), '0.3, 0.1, 0.4, 0.8');
      expect(fieldText(tester, 'segment-0-eyes'), '0.3, 0.25, 0.4, 0.2');
      expect(fieldText(tester, 'segment-1-question'), '');
      expect(fieldText(tester, 'comprehension-0-prompt'), 'What colour was the train?');
      expect(fieldText(tester, 'comprehension-0-options'), 'Red\nBlue');
      expect(fieldText(tester, 'comprehension-0-correct'), 'Red');
      // Media: one uploaded, one missing.
      expect(tester.widget<Text>(off('media-state-s1.webm')).data, 'Uploaded');
      expect(tester.widget<Text>(off('media-state-s2.webm')).data, 'Missing');
    });

    testWidgets('a new item: fill it in, save, and the definition is what the '
        'server expects', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openContent(tester, bed);
      await tester.tap(find.byKey(const Key('new-content')));
      await tester.pumpAndSettle();

      await typeInto(tester, 'content-title', 'Boats');
      await typeInto(tester, 'tag-field', 'boats');
      await tapKey(tester, 'add-tag');
      await typeInto(tester, 'tag-field', 'sea');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tag-sea')), findsOneWidget);
      // The chip's delete button removes it again.
      await tester.tap(find.descendant(
        of: find.byKey(const Key('tag-sea')),
        matching: find.byType(Icon),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tag-sea')), findsNothing);
      await typeInto(tester, 'face-id', 'f9');
      await typeInto(tester, 'voice-id', 'v9');

      await typeInto(tester, 'segment-0-media', 'b1.webm');
      await typeInto(tester, 'segment-0-duration', '12.5');
      await typeInto(tester, 'segment-0-text', 'Hello {{display_name}}!');
      await typeInto(tester, 'segment-0-question', 'Sail or row?');
      await typeInto(tester, 'segment-0-options', 'Sail=s2\nRow=s3\nNeither');
      await typeInto(tester, 'segment-0-face', '0.3, 0.1, 0.4, 0.8');
      await typeInto(tester, 'segment-0-eyes', '0.3 0.25 0.4 0.2');
      await typeInto(tester, 'segment-0-mouth', '0.3,0.55,0.4,0.25');
      await tapKey(tester, 'add-segment');
      await typeInto(tester, 'segment-1-media', 'b2.webm');
      await typeInto(tester, 'segment-1-duration', '8');
      await tapKey(tester, 'add-comprehension');
      await typeInto(tester, 'comprehension-0-prompt', 'What was sailed?');
      await typeInto(tester, 'comprehension-0-options', 'A boat\nA train');
      await typeInto(tester, 'comprehension-0-correct', 'A boat');

      await tapKey(tester, 'save-content');
      expect(find.text('Draft saved.'), findsOneWidget);
      expect(bed.content.saved, hasLength(1));
      final saved = bed.content.saved.single;
      expect(saved['title'], 'Boats');
      expect(saved['topic_tags'], ['boats'], reason: 'the second tag was deleted again');
      expect(saved['face_id'], 'f9');
      expect(saved['voice_id'], 'v9');
      final def = saved['definition'] as Map<String, dynamic>;
      expect(def['start_segment'], 's1');
      expect(def['post_segment'], isNull);
      final segments = def['segments'] as List;
      final s1 = segments[0] as Map<String, dynamic>;
      expect(s1['id'], 's1');
      expect(s1['media_key'], 'b1.webm');
      expect(s1['duration_s'], 12.5);
      expect(s1['text'], 'Hello {{display_name}}!');
      expect(s1['face_layout'], {
        'face_box': [0.3, 0.1, 0.4, 0.8],
        'eye_region': [0.3, 0.25, 0.4, 0.2],
        'mouth_region': [0.3, 0.55, 0.4, 0.25],
      });
      expect(s1['question'], {
        'id': 'q_s1',
        'prompt': 'Sail or row?',
        'options': ['Sail', 'Row', 'Neither'],
        'branches': {'Sail': 's2', 'Row': 's3'},
      });
      final s2 = segments[1] as Map<String, dynamic>;
      expect(s2['id'], 's2');
      expect(s2['question'], isNull);
      expect(s2['face_layout'], isNull);
      expect((def['comprehension'] as List).single, {
        'id': 'c1',
        'prompt': 'What was sailed?',
        'options': ['A boat', 'A train'],
        'correct': 'A boat',
      });
      expect(tester.widget<Text>(find.descendant(of: off('content-status'), matching: find.byType(Text, skipOffstage: false), skipOffstage: false)).data, 'Draft');
    });

    testWidgets('a face layout with the wrong number of values is reported',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openContent(tester, bed);
      await tester.tap(find.byKey(const Key('new-content')));
      await tester.pumpAndSettle();
      await typeInto(tester, 'content-title', 'X');
      await typeInto(tester, 'segment-0-media', 'x.webm');
      await typeInto(tester, 'segment-0-face', '0.3, 0.1, 0.4');
      await tapKey(tester, 'save-content');
      expect(find.textContaining('Segment s1: the face box needs four numbers'),
          findsOneWidget);
      expect(bed.content.saved, isEmpty);

      await typeInto(tester, 'segment-0-face', '');
      await typeInto(tester, 'segment-0-duration', 'ten');
      await tapKey(tester, 'save-content');
      expect(find.text('Segment s1: the duration must be a number of seconds.'),
          findsOneWidget);
    });

    testWidgets('a title is needed', (tester) async {
      useWindow(tester, 1000, 1800);
      await openContent(tester, TestBed());
      await tester.tap(find.byKey(const Key('new-content')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'save-content');
      expect(find.text('Give the content a title.'), findsOneWidget);
    });

    testWidgets('a server refusal is shown word for word', (tester) async {
      useWindow(tester, 1000, 1800);
      const message = 'branch Trains points to unknown segment s9';
      final bed = TestBed(
        content: FakeContentRepository()
          ..writeFailure = const ApiException(message, statusCode: 422),
      );
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'save-content');
      expect(find.text(message), findsOneWidget);
    });
  });

  group('media upload', () {
    testWidgets('uploads the picked file for its key and shows progress',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final gate = Completer<void>();
      final bed = TestBed(content: FakeContentRepository()..uploadGate = gate);
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      expect(tester.widget<Text>(off('media-state-s2.webm')).data, 'Missing');

      await reveal(tester, 'upload-s2.webm');
      await tester.tap(find.byKey(const Key('upload-s2.webm')));
      await tester.pump();
      await tester.pump();
      // Half way through the fake upload: progress is visible, no second
      // upload can start.
      expect(bed.mediaPicker.accepts.single, contains('video/webm'));
      expect(off('progress-s2.webm'), findsOneWidget);
      expect(fieldText(tester, 'segment-0-id'), 's1');
      final pct = tester.widget<Text>(off('progress-text-s2.webm')).data!;
      expect(pct, matches(RegExp(r'^\d+ %$')));
      expect(int.parse(pct.split(' ').first), inInclusiveRange(1, 99));
      expect(tester.widget<OutlinedButton>(off('upload-s2.webm')).onPressed, isNull);
      expect(tester.widget<Text>(off('media-state-s2.webm')).data, 'Uploading');

      gate.complete();
      await tester.pumpAndSettle();
      expect(bed.content.uploads.single.key, 's2.webm');
      expect(bed.content.uploads.single.id, '2');
      expect(bed.content.uploads.single.type, 'video/webm');
      expect(bed.content.uploads.single.size, 2000);
      expect(off('progress-s2.webm'), findsNothing);
      expect(tester.widget<Text>(off('media-state-s2.webm')).data, 'Uploaded');
    });

    testWidgets('a cancelled dialog changes nothing', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      bed.mediaPicker.next = null;
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'upload-s2.webm');
      expect(bed.content.uploads, isEmpty);
      expect(tester.widget<Text>(off('media-state-s2.webm')).data, 'Missing');
    });

    testWidgets('a file that is not video or image is refused before upload',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      bed.mediaPicker.next = PickedMedia(
        name: 'notes.pdf',
        bytes: Uint8List(10),
        contentType: 'application/pdf',
      );
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'upload-s2.webm');
      expect(find.text('Use a WebM or MP4 video, or a PNG or JPEG image.'),
          findsOneWidget);
      expect(bed.content.uploads, isEmpty);
    });

    testWidgets('the type comes from the name when the browser gives none',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      bed.mediaPicker.next = PickedMedia(
        name: 'clip.MP4',
        bytes: Uint8List(50),
        contentType: '',
      );
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'upload-s2.webm');
      expect(bed.content.uploads.single.type, 'video/mp4');
    });

    testWidgets('a failed upload shows the server message and can be retried',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository()
          ..uploadFailure = const ApiException('File is too large.', statusCode: 413),
      );
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'upload-s2.webm');
      expect(find.text('File is too large.'), findsOneWidget);
      expect(tester.widget<Text>(off('media-state-s2.webm')).data, 'Missing');

      bed.content.uploadFailure = null;
      await tapKey(tester, 'upload-s2.webm');
      expect(find.text('File is too large.'), findsNothing);
      expect(tester.widget<Text>(off('media-state-s2.webm')).data, 'Uploaded');
    });

    testWidgets('a new item is saved first so the server knows it', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      bed.mediaPicker.next = PickedMedia(
        name: 'b1.webm',
        bytes: Uint8List(300),
        contentType: 'video/webm',
      );
      await openContent(tester, bed);
      await tester.tap(find.byKey(const Key('new-content')));
      await tester.pumpAndSettle();
      await typeInto(tester, 'content-title', 'Boats');
      await typeInto(tester, 'segment-0-media', 'b1.webm');
      expect(tester.widget<Text>(off('media-state-b1.webm')).data, 'Missing');
      await tapKey(tester, 'upload-b1.webm');
      expect(bed.content.saved, hasLength(1));
      expect(bed.content.uploads.single.key, 'b1.webm');
      expect(tester.widget<Text>(off('media-state-b1.webm')).data, 'Uploaded');
    });
  });

  group('approval', () {
    testWidgets('missing media are listed when the server refuses (422)',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository()
          ..approveFailure = const ApiException(
            'missing media: s2.webm',
            statusCode: 422,
            body: {'detail': 'missing media: s2.webm', 'missing_media': ['s2.webm']},
          ),
      );
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'approve-content');

      expect(find.text('missing media: s2.webm'), findsOneWidget,
          reason: 'the server message, verbatim');
      final box = find.byKey(const Key('approve-missing'), skipOffstage: false);
      await tester.ensureVisible(box);
      await tester.pumpAndSettle();
      expect(box, findsOneWidget);
      expect(find.text('•  s2.webm'), findsOneWidget);
      expect(bed.content.approved, isEmpty);
      expect(find.byKey(const Key('content-status'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('the list comes from the message when the body has no field',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository()
          ..approveFailure = const ApiException(
            'missing media: s1.webm, s2.webm',
            statusCode: 422,
          ),
      );
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'approve-content');
      await tester.ensureVisible(off('approve-missing'));
      await tester.pumpAndSettle();
      expect(find.text('•  s1.webm'), findsOneWidget);
      expect(find.text('•  s2.webm'), findsOneWidget);
    });

    testWidgets('after uploading the missing file the approval goes through and '
        'the item becomes read-only', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openContent(tester, bed);
      await tapKey(tester, 'open-content-2');
      await tapKey(tester, 'upload-s2.webm');
      await tapKey(tester, 'approve-content');

      expect(bed.content.approved, ['2']);
      expect(find.text('Content approved. It can now be attached to assignments.'),
          findsOneWidget);
      expect(off('approved-note'), findsOneWidget);
      expect(off('save-content'), findsNothing);
      expect(off('approve-content'), findsNothing);
      expect(off('upload-s2.webm'), findsNothing);
      expect(tester.widget<TextFormField>(off('content-title')).enabled, isFalse);
    });

    testWidgets('approved content opens read-only', (tester) async {
      useWindow(tester, 1000, 1800);
      await openContent(tester, TestBed());
      await tapKey(tester, 'open-content-1');
      expect(off('approved-note'), findsOneWidget);
      expect(off('add-segment'), findsNothing);
      expect(off('save-content'), findsNothing);
    });

    testWidgets('an unsaved item is saved before it is approved', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openContent(tester, bed);
      await tester.tap(find.byKey(const Key('new-content')));
      await tester.pumpAndSettle();
      await typeInto(tester, 'content-title', 'Quick');
      await tapKey(tester, 'approve-content');
      expect(bed.content.saved, hasLength(1));
      expect(bed.content.approved, hasLength(1));
    });
  });
}

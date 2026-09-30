import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/ai/presentation/ai_widgets.dart';

import 'fakes.dart';
import 'helpers.dart';

/// Step 5 in the content editor: "Text reviewed" and "Generate videos".

Finder off(String key) => find.byKey(Key(key), skipOffstage: false);

Future<void> reveal(WidgetTester tester, String key) async {
  await tester.ensureVisible(off(key));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await reveal(tester, key);
  await tester.tap(off(key));
  await tester.pumpAndSettle();
}

Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await reveal(tester, key);
  await tester.enterText(off(key), text);
  await tester.pump();
}

Future<void> openEditor(
  WidgetTester tester,
  TestBed bed,
  String id, {
  String role = 'researcher',
}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Content');
  await tapKey(tester, 'open-content-$id');
}

ContentDetail draft(
  String id, {
  bool reviewed = false,
  List<String> missing = const ['s1.webm', 's2.webm'],
  String status = ContentStatus.draft,
}) =>
    ContentDetail(
      summary: ContentSummary(
        id: id,
        title: 'AI draft: trains',
        topicTags: const ['trains'],
        faceId: 'f1',
        voiceId: 'v1',
        status: status,
        mediaKeys: const ['s1.webm', 's2.webm'],
        missingMedia: missing,
        textReviewed: reviewed,
      ),
      definition: sampleContentDefinition(),
    );

bool enabled(WidgetTester tester, String key) {
  final w = tester.widget<ButtonStyleButton>(off(key));
  return w.onPressed != null;
}

String chipLabel(WidgetTester tester) => tester
    .widget<StateChip>(off('text-reviewed-status'))
    .label;

String? reason(WidgetTester tester) {
  final f = off('video-blocked-reason');
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

void main() {
  group('text review', () {
    testWidgets('the list says Yes or No for every item', (tester) async {
      useWindow(tester, 1440, 900);
      final bed = TestBed(
        content: FakeContentRepository(items: [
          draft('1', reviewed: true),
          draft('2'),
        ]),
      );
      await openStudy(tester, bed);
      await openTab(tester, 'Content');
      expect(find.text('Text reviewed'), findsOneWidget);
      expect(tester.widget<Text>(off('text-reviewed-1')).data, 'Yes');
      expect(tester.widget<Text>(off('text-reviewed-2')).data, 'No');
    });

    testWidgets('Mark text reviewed posts once and flips the status',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openEditor(tester, bed, '2');

      expect(chipLabel(tester), 'Text reviewed: no');
      expect(enabled(tester, 'mark-text-reviewed'), isTrue);
      await tapKey(tester, 'mark-text-reviewed');

      expect(bed.content.reviewed, ['2']);
      expect(chipLabel(tester), 'Text reviewed: yes');
      expect(enabled(tester, 'mark-text-reviewed'), isFalse,
          reason: 'nothing left to mark');
      expect(find.textContaining('Text marked as reviewed'), findsOneWidget);
    });

    testWidgets('unsaved edits are saved first so the marked text is the text read',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openEditor(tester, bed, '2');
      await typeInto(tester, 'content-title', 'Planes, edited');
      await tapKey(tester, 'mark-text-reviewed');

      expect(bed.content.saved.map((s) => s['title']), ['Planes, edited']);
      expect(bed.content.reviewed, ['2']);
      expect(chipLabel(tester), 'Text reviewed: yes');
    });

    testWidgets('editing reviewed text and saving resets the review',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository(items: [draft('5', reviewed: true)]),
      );
      await openEditor(tester, bed, '5');
      expect(chipLabel(tester), 'Text reviewed: yes');

      await typeInto(tester, 'segment-0-text', 'A new first line');
      await tapKey(tester, 'save-content');
      expect(chipLabel(tester), 'Text reviewed: no');
      expect(enabled(tester, 'mark-text-reviewed'), isTrue);
    });

    testWidgets('approved content cannot be marked', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openEditor(tester, bed, '1');
      expect(chipLabel(tester), 'Text reviewed: no');
      expect(enabled(tester, 'mark-text-reviewed'), isFalse);
      expect(bed.content.reviewed, isEmpty);
    });

    testWidgets('analysts see the status but have no button', (tester) async {
      useWindow(tester, 1000, 1800);
      await openEditor(tester, TestBed(), '2', role: 'analyst');
      expect(chipLabel(tester), 'Text reviewed: no');
      expect(off('mark-text-reviewed'), findsNothing);
      expect(reason(tester), contains('Researchers'));
    });

    testWidgets('a refusal is shown as the server wrote it', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository()
          ..reviewFailure =
              const ApiException('Content is not a draft.', statusCode: 409),
      );
      await openEditor(tester, bed, '2');
      await tapKey(tester, 'mark-text-reviewed');
      expect(find.text('Content is not a draft.'), findsOneWidget);
      expect(chipLabel(tester), 'Text reviewed: no');
    });
  });

  group('Generate videos', () {
    testWidgets('is disabled with the reason until the text is reviewed',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed();
      await openEditor(tester, bed, '2');

      expect(off('video-section'), findsOneWidget);
      expect(enabled(tester, 'generate-videos'), isFalse);
      expect(reason(tester), contains('Mark the text reviewed first'));

      await tapKey(tester, 'mark-text-reviewed');
      expect(enabled(tester, 'generate-videos'), isTrue);
      expect(reason(tester), isNull);
      expect(bed.ai.videoRequests, isEmpty);
    });

    testWidgets('lists only the segments that lack media, all ticked',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository(items: [draft('5', reviewed: true)]),
      );
      await openEditor(tester, bed, '5');
      for (final id in ['s1', 's2']) {
        final box = tester.widget<CheckboxListTile>(off('video-segment-$id'));
        expect(box.value, isTrue, reason: id);
      }

      // Segment s1 has its upload: it is not offered.
      final one = TestBed(content: FakeContentRepository()..items = [
        draft('6', reviewed: true, missing: const ['s2.webm']),
      ]);
      await tester.pumpWidget(const SizedBox());
      await openEditor(tester, one, '6');
      expect(off('video-segment-s1'), findsNothing);
      expect(off('video-segment-s2'), findsOneWidget);
    });

    testWidgets('creates one job for each ticked segment and links to the AI tab',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository(items: [draft('5', reviewed: true)]),
      );
      await openEditor(tester, bed, '5');
      await typeInto(tester, 'video-face-id', 'face-9');
      await typeInto(tester, 'video-voice-id', 'voice-3');
      await tapKey(tester, 'video-segment-s1'); // untick s1
      await tapKey(tester, 'generate-videos');

      expect(bed.ai.videoRequests, hasLength(1));
      expect(bed.ai.videoRequests.single.toJson(), {
        'content_id': 5,
        'segment_ids': ['s2'],
        'face_id': 'face-9',
        'voice_id': 'voice-3',
      });
      final created = off('video-jobs-created');
      await reveal(tester, 'video-jobs-created');
      expect(created, findsOneWidget);
      expect(find.text('1 video job created'), findsOneWidget);
      expect(find.textContaining('segment s2'), findsOneWidget);
      expect(find.descendant(of: created, matching: find.text('Queued')),
          findsOneWidget);

      // The link leaves the editor for the AI tab, where the job is listed.
      await tapKey(tester, 'open-ai-tab');
      expect(off('ai-status-card'), findsOneWidget);
      expect(off('job-status-100'), findsOneWidget);
    });

    testWidgets('all segments ticked: every one without media gets a job',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository(items: [draft('5', reviewed: true)]),
      );
      await openEditor(tester, bed, '5');
      await tapKey(tester, 'generate-videos');
      expect(bed.ai.videoRequests.single.segmentIds, ['s1', 's2']);
      expect(find.text('2 video jobs created'), findsOneWidget);
    });

    testWidgets('with every segment unticked there is nothing to generate',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository(items: [draft('5', reviewed: true)]),
      );
      await openEditor(tester, bed, '5');
      await tapKey(tester, 'video-segment-s1');
      await tapKey(tester, 'video-segment-s2');
      expect(enabled(tester, 'generate-videos'), isFalse);
      expect(reason(tester), 'Select at least one segment.');
    });

    testWidgets('a text edit that is not saved blocks it', (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository(items: [draft('5', reviewed: true)]),
      );
      await openEditor(tester, bed, '5');
      await typeInto(tester, 'segment-0-text', 'Changed');
      expect(enabled(tester, 'generate-videos'), isFalse);
      expect(reason(tester), contains('Save your changes first'));
    });

    testWidgets('nothing to generate when every segment has media',
        (tester) async {
      useWindow(tester, 1000, 1800);
      final bed = TestBed(
        content: FakeContentRepository(
          items: [draft('5', reviewed: true, missing: const [])],
        ),
      );
      await openEditor(tester, bed, '5');
      expect(off('no-lacking-segments'), findsOneWidget);
      expect(enabled(tester, 'generate-videos'), isFalse);
      expect(reason(tester), 'Every segment already has media.');
    });

    testWidgets('approved content has all its media and is not offered videos',
        (tester) async {
      useWindow(tester, 1000, 1800);
      await openEditor(tester, TestBed(), '1');
      expect(enabled(tester, 'generate-videos'), isFalse);
      expect(reason(tester), contains('Approved content'));
    });

    for (final detail in [
      'Mark the text reviewed before generating videos.',
      'budget_exceeded: estimate 0.80 exceeds the remaining 0.10 units',
      'provider_not_configured: no API key for the video provider',
    ]) {
      testWidgets('the server refusal is shown verbatim: ${detail.split(':').first}',
          (tester) async {
        useWindow(tester, 1000, 1800);
        final bed = TestBed(
          content: FakeContentRepository(items: [draft('5', reviewed: true)]),
          ai: FakeAiRepository()
            ..videoJobFailure = ApiException(
              detail,
              statusCode: detail.startsWith('Mark') ? 409 : 422,
            ),
        );
        await openEditor(tester, bed, '5');
        await tapKey(tester, 'generate-videos');
        expect(
          find.descendant(of: off('video-error'), matching: find.text(detail)),
          findsOneWidget,
        );
        expect(off('video-jobs-created'), findsNothing);
        expect(enabled(tester, 'generate-videos'), isTrue,
            reason: 'the researcher can try again');
      });
    }

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the review and video sections fit ${width.toInt()} px',
          (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        final bed = TestBed(
          content: FakeContentRepository(items: [draft('5')]),
        );
        await openEditor(tester, bed, '5');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'mark-text-reviewed');
        await typeInto(tester, 'video-face-id', 'a-long-face-identifier-0001');
        await tapKey(tester, 'generate-videos');
        await reveal(tester, 'video-jobs-created');
        await reveal(tester, 'open-ai-tab');
        expect(tester.takeException(), isNull);
      });
    }
  });
}

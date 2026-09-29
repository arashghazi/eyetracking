import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openSessions(WidgetTester tester, TestBed bed,
    {String role = 'researcher'}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Sessions');
}

/// The page is a lazy list: scroll until [finder] has been built.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Sessions tab', () {
    testWidgets('lists every session with its quality figures', (tester) async {
      useWindow(tester, 1440, 900);
      await openSessions(tester, TestBed());

      final table = find.byKey(const Key('sessions-table'));
      expect(table, findsOneWidget);
      for (final header in [
        'Participant',
        'Created',
        'Status',
        'Estimator',
        'Calibration',
        'Validation',
        'Classifiable',
        'Eye-region attention',
      ]) {
        expect(find.descendant(of: table, matching: find.text(header)),
            findsOneWidget);
      }
      // P-001: synthetic, failed validation, not evaluable.
      expect(find.text('P-001'), findsOneWidget);
      expect(find.text('2026-09-29 08:00 UTC'), findsOneWidget);
      expect(find.byKey(const Key('synthetic-badge')), findsOneWidget);
      expect(find.text('88 px'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('70 %'), findsOneWidget);
      // P-002: no validation yet and no coverage.
      expect(find.text('52 px'), findsOneWidget);
      // P-003: passed validation, evaluable eye-region share.
      expect(find.text('Passed'), findsOneWidget);
      expect(find.text('43 %'), findsOneWidget);
      expect(find.text('Not evaluable'), findsNWidgets(2));
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('an empty study says so', (tester) async {
      useWindow(tester, 800, 900);
      final bed = TestBed(sessions: FakeSessionsRepository(items: const []));
      await openSessions(tester, bed);
      expect(find.textContaining('No sessions yet'), findsOneWidget);
    });

    testWidgets('a failed load shows the message', (tester) async {
      useWindow(tester, 800, 900);
      final repo = FakeSessionsRepository()
        ..failure = const ApiException('Not a member of this study.',
            statusCode: 403);
      await openSessions(tester, TestBed(sessions: repo));
      expect(find.text('Not a member of this study.'), findsOneWidget);
    });

    testWidgets('analysts can read the sessions too', (tester) async {
      useWindow(tester, 1440, 900);
      await openSessions(tester, TestBed(), role: 'analyst');
      expect(find.byKey(const Key('sessions-table')), findsOneWidget);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('renders without overflow at ${width.toInt()} px',
          (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        await openSessions(tester, TestBed());
        expect(find.byKey(const Key('sessions-table')), findsOneWidget);
        expect(find.text('Not evaluable'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Session detail', () {
    Future<void> openDetail(WidgetTester tester, TestBed bed) async {
      await openSessions(tester, bed);
      await tester.tap(find.text('P-001'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the four cards, Not evaluable and its reason',
        (tester) async {
      useWindow(tester, 1440, 1600);
      await openDetail(tester, TestBed());

      expect(find.text('Session of P-001'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      for (final title in [
        'Face-region attention',
        'Eye-region attention',
        'Comprehension',
        'Comfort',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.descendant(
        of: find.byKey(const Key('card-face')),
        matching: find.text('70 %'),
      ), findsOneWidget);
      expect(find.descendant(
        of: find.byKey(const Key('card-eye')),
        matching: find.text('Not evaluable'),
      ), findsOneWidget);
      expect(find.text('Regional validation did not pass.'), findsOneWidget);
      expect(find.descendant(
        of: find.byKey(const Key('card-comprehension')),
        matching: find.text('—'),
      ), findsOneWidget);
      expect(find.descendant(
        of: find.byKey(const Key('card-comfort')),
        matching: find.text('—'),
      ), findsOneWidget);
      expect(find.byKey(const Key('synthetic-badge')), findsOneWidget);
    });

    testWidgets('shows device, calibration, validation, segments and events',
        (tester) async {
      useWindow(tester, 1440, 3000);
      await openDetail(tester, TestBed());

      expect(find.text('Mozilla/5.0 Test'), findsOneWidget);
      expect(find.text('1440 x 900 px, 1.25x pixel ratio'), findsOneWidget);
      expect(find.text('Integrated Camera (640 x 480)'), findsOneWidget);
      expect(find.text('stub-1 0.1'), findsOneWidget);
      expect(find.text('88.4 px'), findsWidgets);
      expect(find.text('141.0 px'), findsOneWidget);
      expect(find.text('Correct share is below 80 %.'), findsOneWidget);

      final targets = find.byKey(const Key('validation-targets'));
      expect(targets, findsOneWidget);
      expect(find.descendant(of: targets, matching: find.text('Eyes')),
          findsOneWidget);
      expect(find.descendant(of: targets, matching: find.text('Mouth')),
          findsWidgets);
      expect(find.descendant(of: targets, matching: find.text('Rest of the face')),
          findsOneWidget);

      expect(find.text('baseline'), findsOneWidget);
      expect(find.text('00:04.000'), findsWidgets);
      expect(find.text('00:34.000'), findsWidgets);
      final events = find.byKey(const Key('section-events'));
      expect(find.descendant(of: events, matching: find.textContaining('segment_start')),
          findsOneWidget);
      expect(find.descendant(of: events, matching: find.textContaining('face_lost')),
          findsOneWidget);
      expect(find.descendant(of: events, matching: find.textContaining('completed')),
          findsOneWidget);
    });

    testWidgets('Load samples pages through and shows the first 200 rows',
        (tester) async {
      useWindow(tester, 1440, 1000);
      final bed = TestBed();
      await openDetail(tester, bed);

      await scrollTo(tester, find.byKey(const Key('samples-count')));
      expect(find.text('Samples: 250'), findsOneWidget,
          reason: 'the count is known before the samples are loaded');
      expect(bed.sessions.sampleRequests, [(offset: 0, limit: 1)]);
      expect(find.byKey(const Key('samples-table')), findsNothing);

      await tester.tap(find.byKey(const Key('load-samples')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('samples-table')));

      expect(bed.sessions.sampleRequests.skip(1), [
        (offset: 0, limit: 100),
        (offset: 100, limit: 100),
      ]);
      final table = tester.widget<DataTable>(find.descendant(
        of: find.byKey(const Key('samples-table')),
        matching: find.byType(DataTable),
      ));
      expect(table.rows, hasLength(200));
      expect(find.textContaining('Showing the first 200 of 250 samples'),
          findsOneWidget);
    });

    testWidgets('a short session shows every row', (tester) async {
      useWindow(tester, 1440, 1000);
      final bed = TestBed(sessions: FakeSessionsRepository(sampleTotal: 30));
      await openDetail(tester, bed);
      await scrollTo(tester, find.byKey(const Key('load-samples')));
      await tester.tap(find.byKey(const Key('load-samples')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('samples-table')));
      final table = tester.widget<DataTable>(find.descendant(
        of: find.byKey(const Key('samples-table')),
        matching: find.byType(DataTable),
      ));
      expect(table.rows, hasLength(30));
      expect(bed.sessions.sampleRequests.length, 2);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('detail has no overflow at ${width.toInt()} px',
          (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        final bed = TestBed();
        await openDetail(tester, bed);
        expect(find.text('Session of P-001'), findsOneWidget);
        await scrollTo(tester, find.byKey(const Key('load-samples')));
        await tester.tap(find.byKey(const Key('load-samples')));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.byKey(const Key('samples-table')));
        expect(find.byKey(const Key('samples-table')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

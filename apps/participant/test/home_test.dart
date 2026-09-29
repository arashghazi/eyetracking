import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:participant_app/features/home/domain/participant_overview.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('home renders without overflow at ${width.toInt()} px',
        (tester) async {
      useWindow(tester, width, width == 360 ? 640 : 900);
      final bed = TestBed(home: FakeHomeRepository(reasons: const [
        ReadinessReason.consentMissingOrOutdated,
        ReadinessReason.demographicsIncomplete,
      ]));
      await pumpApp(tester, bed);

      expect(find.text('P-0001'), findsOneWidget);
      expect(find.text('Information sheet & consent'), findsOneWidget);
      expect(find.text('Demographics'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      // The lower cards may start below the fold on a short screen.
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text(
          'You can pause or end a session at any time, and come back whenever you like.',
        ),
        200,
        scrollable: scrollable,
      );
      await tester.scrollUntilVisible(
        find.text('Download my data'),
        200,
        scrollable: scrollable,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('checklist reflects readiness reasons', (tester) async {
    useWindow(tester, 800, 1000);
    final bed = TestBed(home: FakeHomeRepository(reasons: const [
      ReadinessReason.demographicsIncomplete,
    ]));
    await pumpApp(tester, bed);

    expect(find.text('A few steps are still open'), findsOneWidget);
    expect(find.textContaining('Your consent is on file'), findsOneWidget);
    expect(find.textContaining('A few questions the research team needs'),
        findsOneWidget);
    // Consent step is done, so it offers a review.
    expect(
      find.descendant(
        of: find.byKey(const Key('open-consent')),
        matching: find.text('Review'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ready participant sees the ready message', (tester) async {
    useWindow(tester, 800, 1000);
    await pumpApp(tester, TestBed());
    expect(find.text('You are ready to start'), findsOneWidget);
  });

  testWidgets('Download my data shows the JSON in a monospace view',
      (tester) async {
    useWindow(tester, 800, 1000);
    await pumpApp(tester, TestBed());

    await tester.tap(find.byKey(const Key('download-data')));
    await tester.pumpAndSettle();

    final json = tester.widget<SelectableText>(find.byKey(const Key('data-json')));
    expect(json.data, contains('"code": "P-0001"'));
    expect(json.style?.fontFamily, 'monospace');
  });

  testWidgets('a failing home load shows a banner and a retry', (tester) async {
    useWindow(tester, 800, 1000);
    await pumpApp(tester, TestBed(home: _FailingHome()));
    expect(
      find.text('Could not reach the server. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}

class _FailingHome extends FakeHomeRepository {
  @override
  Future<ParticipantOverview> loadOverview() async => throw const ApiException(
        'Could not reach the server. Check your connection and try again.',
      );
}

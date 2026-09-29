import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

FilledButton submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('consent-submit')));

void main() {
  testWidgets('submit is disabled until "I agree to take part" is checked',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed(home: FakeHomeRepository(reasons: const [
      ReadinessReason.consentMissingOrOutdated,
    ]));
    await pumpApp(tester, bed);
    await openStep(tester, 'consent');

    // Five headings, in order.
    final headings = [
      'Aims of the study',
      'Possible sources of discomfort',
      'Possible benefits',
      'How your data is handled',
      'Stopping and starting again',
    ];
    final dy = [for (final h in headings) tester.getTopLeft(find.text(h)).dy];
    expect(dy, orderedEquals([...dy]..sort()));
    expect(find.text('I agree to take part'), findsOneWidget);
    expect(find.text('Allow audio recording'), findsOneWidget);
    expect(find.text('Allow video recording'), findsOneWidget);

    expect(submitButton(tester).onPressed, isNull);

    // Optional boxes alone do not enable submit.
    await tester.tap(find.byKey(const Key('audio-checkbox')));
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('agree-checkbox')));
    await tester.pump();
    expect(submitButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('consent-submit')));
    await tester.pumpAndSettle();
    expect(bed.consent.given, [
      {
        'sheet_version': 3,
        'participate': true,
        'audio_recording': true,
        'video_recording': false,
      }
    ]);
    // Status view with a withdraw button replaces the form.
    expect(find.byKey(const Key('withdraw-button')), findsOneWidget);
    expect(find.text('Your consent has been recorded.'), findsOneWidget);

  });

  testWidgets('withdrawing needs confirmation', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed(
      consent: FakeConsentRepository(
        consent: const Consent(
          sheetVersion: 3,
          participate: true,
          givenAt: '2026-09-02T09:30:00Z',
        ),
      ),
    );
    await pumpApp(tester, bed);
    await openStep(tester, 'consent');

    expect(find.byKey(const Key('agree-checkbox')), findsNothing);
    await tester.tap(find.byKey(const Key('withdraw-button')));
    await tester.pumpAndSettle();
    expect(find.text('Withdraw consent?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('withdraw-cancel')));
    await tester.pumpAndSettle();
    expect(bed.consent.withdrawCalls, 0);

    await tester.tap(find.byKey(const Key('withdraw-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('withdraw-confirm')));
    await tester.pumpAndSettle();
    expect(bed.consent.withdrawCalls, 1);
    // Back to the form, submit disabled again.
    expect(find.byKey(const Key('agree-checkbox')), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('outdated consent asks for agreement again', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed(
      consent: FakeConsentRepository(
        consent: const Consent(sheetVersion: 2, participate: true),
      ),
    );
    await pumpApp(tester, bed);
    await openStep(tester, 'consent');

    expect(find.textContaining('has changed since you last answered'),
        findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('no published sheet is explained', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed(
      home: FakeHomeRepository(
        reasons: const [ReadinessReason.noInformationSheet],
      ),
      consent: FakeConsentRepository(sheet: null),
    );
    await pumpApp(tester, bed);
    // The step is not openable yet.
    final button = tester.widget<OutlinedButton>(find.byKey(const Key('open-consent')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('not published the information sheet'),
        findsOneWidget);
  });
}

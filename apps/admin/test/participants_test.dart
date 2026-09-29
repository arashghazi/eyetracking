import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

/// Counts widgets showing [text] on the same table row as the cell [code].
/// (DataRow keys are not part of the widget tree, so match by position.)
int inRow(WidgetTester tester, String code, String text) {
  final rowY = tester.getCenter(find.text(code)).dy;
  final matches = find.text(text);
  var count = 0;
  for (var i = 0; i < matches.evaluate().length; i++) {
    if ((tester.getCenter(matches.at(i)).dy - rowY).abs() < 20) count++;
  }
  return count;
}

void main() {
  testWidgets('participants table shows readiness, reasons, consent, demographics',
      (tester) async {
    useWindow(tester, 1440);
    await openStudy(tester, TestBed());

    for (final header in [
      'Code',
      'Ready',
      'Reasons',
      'Consent version',
      'Demographics complete',
    ]) {
      expect(find.text(header), findsOneWidget);
    }
    expect(find.text('3 total, 1 ready'), findsOneWidget);

    // Ready participant: two "Yes", consent version 3.
    expect(inRow(tester, 'P-001', 'Yes'), 2);
    expect(inRow(tester, 'P-001', '3'), 1);

    // Waiting participant: not ready, both reasons, no consent, demographics incomplete.
    expect(inRow(tester, 'P-002', 'No'), 2);
    expect(
      inRow(tester, 'P-002', 'Consent missing or outdated, Demographics incomplete'),
      1,
    );
    expect(inRow(tester, 'P-002', 'None'), 1);

    // Withdrawn consent is flagged; demographics are complete for this one.
    expect(inRow(tester, 'P-003', '2 (withdrawn)'), 1);
    expect(inRow(tester, 'P-003', 'Yes'), 1);
    expect(inRow(tester, 'P-003', 'No'), 1);
  });

  testWidgets('an empty study explains what to do', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed(participants: FakeParticipantsRepository()..records = []);
    await openStudy(tester, bed);
    expect(find.textContaining('No participants yet'), findsOneWidget);
  });

  testWidgets('row tap opens the detail and identity can be revealed',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openStudy(tester, bed);

    await tester.tap(find.text('P-001'));
    await tester.pumpAndSettle();

    expect(find.text('Participant P-001'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget); // display name
    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.byKey(const Key('identity-email')), findsNothing);

    await tapVisible(tester, find.byKey(const Key('reveal-identity')));
    expect(bed.participants.identityRequests, ['P-001']);
    expect(find.text('sam@example.org'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('hide-identity')));
    expect(find.text('sam@example.org'), findsNothing);
    expect(find.byKey(const Key('reveal-identity')), findsOneWidget);
  });

  testWidgets('revealing identity without the grant shows a clear message',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed(
      participants: FakeParticipantsRepository()
        ..identityFailure = const ApiException('forbidden', statusCode: 403),
    );
    await openStudy(tester, bed);
    await tester.tap(find.text('P-002'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const Key('reveal-identity')));

    expect(find.textContaining('do not have permission to see participant identities'),
        findsOneWidget);
    expect(find.text('sam@example.org'), findsNothing);
    // The button stays available for another try.
    expect(find.byKey(const Key('reveal-identity')), findsOneWidget);
  });
}

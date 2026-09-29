import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('creating an invitation shows token and code with copy buttons',
      (tester) async {
    useWindow(tester, 800, 1200);
    final copied = captureClipboard(tester);
    final bed = TestBed();
    await openStudy(tester, bed);
    await openTab(tester, 'Invitations');

    // Default expiry is 14 days.
    expect(find.widgetWithText(TextField, '14'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('invitee-email')),
      'new.person@example.org',
    );
    await tester.tap(find.byKey(const Key('create-invitation')));
    await tester.pumpAndSettle();

    expect(bed.invitations.requests, [
      {'email': 'new.person@example.org', 'days': 14},
    ]);
    expect(find.text('Invitation created'), findsOneWidget);
    expect(find.text('tok-abc-1'), findsOneWidget);
    expect(find.text('P-004'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-token-0')));
    await tester.pumpAndSettle();
    expect(copied, ['tok-abc-1']);
    expect(find.text('Token copied to the clipboard.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-code-0')));
    await tester.pumpAndSettle();
    expect(copied, ['tok-abc-1', 'P-004']);
  });

  testWidgets('invitee email is optional and expiry is validated',
      (tester) async {
    useWindow(tester, 800, 1200);
    final bed = TestBed();
    await openStudy(tester, bed);
    await openTab(tester, 'Invitations');

    await tester.enterText(find.byKey(const Key('expires-days')), '365');
    await tester.tap(find.byKey(const Key('create-invitation')));
    await tester.pumpAndSettle();
    expect(find.textContaining('from 1 to 90'), findsWidgets);
    expect(bed.invitations.requests, isEmpty);

    await tester.enterText(find.byKey(const Key('expires-days')), '7');
    await tester.tap(find.byKey(const Key('create-invitation')));
    await tester.pumpAndSettle();
    expect(bed.invitations.requests, [
      {'email': null, 'days': 7},
    ]);
  });
}

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('admin adds a member with the identity-link grant',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openStudy(tester, bed);
    await openTab(tester, 'Members');

    // Missing id is rejected client-side.
    await tapVisible(tester, find.byKey(const Key('add-member')));
    expect(find.textContaining('numeric user id'), findsOneWidget);
    expect(bed.members.added, isEmpty);

    await tester.enterText(find.byKey(const Key('member-user-id')), '12');
    await tester.tap(find.byKey(const Key('member-study-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyst').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-can-link')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('add-member')));

    expect(bed.members.added, [
      {'study': 1, 'user': 12, 'role': 'analyst', 'link': true},
    ]);
    expect(find.textContaining('User 12 was added as analyst'), findsOneWidget);
  });

  testWidgets('creating a staff account fills in the user id', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openStudy(tester, bed);
    await openTab(tester, 'Members');

    await tester.enterText(find.byKey(const Key('staff-email')), 'new@example.org');
    await tester.enterText(find.byKey(const Key('staff-password')), 'short');
    await tapVisible(tester, find.byKey(const Key('create-staff')));
    expect(find.textContaining('at least 8 characters'), findsWidgets);
    expect(bed.members.staff, isEmpty);

    await tester.enterText(find.byKey(const Key('staff-password')), 'long-enough-1');
    await tester.tap(find.byKey(const Key('staff-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyst').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('create-staff')));

    expect(bed.members.staff, [
      {'email': 'new@example.org', 'role': 'analyst'},
    ]);
    expect(find.textContaining('Account created for new@example.org'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, '41'), findsOneWidget);
  });

  testWidgets('a server refusal is shown in a banner', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    bed.members.failure =
        const ApiException('already a member', statusCode: 409);
    await openStudy(tester, bed);
    await openTab(tester, 'Members');

    await tester.enterText(find.byKey(const Key('member-user-id')), '3');
    await tapVisible(tester, find.byKey(const Key('add-member')));
    expect(find.text('already a member'), findsOneWidget);
  });
}

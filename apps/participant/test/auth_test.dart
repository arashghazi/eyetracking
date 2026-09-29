import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('sign-in shows the API error in a banner', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    bed.authRepository.failure =
        const ApiException('Invalid email or password', statusCode: 401);
    await pumpApp(tester, bed, signedIn: false);

    await tester.enterText(find.byKey(const Key('email')), 'sam@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'wrong-pass');
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(MessageBanner), findsOneWidget);
    expect(find.text('Invalid email or password'), findsOneWidget);
    // Still on the sign-in screen, and the banner can be dismissed.
    expect(find.text('Sign in'), findsWidgets);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageBanner), findsNothing);
  });

  testWidgets('sign-in with Enter key submits and shows home', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    await pumpApp(tester, bed, signedIn: false);

    await tester.enterText(find.byKey(const Key('email')), 'sam@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'password1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(bed.authRepository.signedInWith, ['sam@example.org']);
    expect(find.byKey(const Key('research-code')), findsOneWidget);
  });

  testWidgets('a staff account is refused by the Participant App',
      (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    bed.authRepository.role = 'researcher';
    await pumpApp(tester, bed, signedIn: false);

    await tester.enterText(find.byKey(const Key('email')), 'staff@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'password1');
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a participant account'), findsOneWidget);
    expect(bed.authRepository.signedOut, isTrue);
    expect(find.byKey(const Key('research-code')), findsNothing);
  });

  testWidgets('invitation form requires a password of at least 8 characters',
      (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    await pumpApp(tester, bed, signedIn: false);

    await tester.tap(find.byKey(const Key('have-invitation')));
    await tester.pumpAndSettle();
    expect(find.text('Accept your invitation'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('invitation-token')), 'tok-123');
    await tester.enterText(find.byKey(const Key('email')), 'new@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'short');
    await tester.tap(find.byKey(const Key('accept-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(bed.authRepository.acceptedTokens, isEmpty);

    await tester.enterText(find.byKey(const Key('password')), 'long-enough-1');
    await tester.tap(find.byKey(const Key('accept-submit')));
    await tester.pumpAndSettle();
    expect(bed.authRepository.acceptedTokens, ['tok-123']);
    // Signed in: the home screen replaces the invitation form.
    expect(find.byKey(const Key('research-code')), findsOneWidget);
    expect(find.text('Accept your invitation'), findsNothing);
  });

  testWidgets('signing out returns to the sign-in screen', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    await pumpApp(tester, bed);

    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-submit')), findsOneWidget);
    expect(bed.authRepository.signedOut, isTrue);
  });

  testWidgets('an expired session closes open screens and explains why',
      (tester) async {
    useWindow(tester, 800, 1200);
    final bed = TestBed();
    await pumpApp(tester, bed);
    await openStep(tester, 'profile');
    expect(find.text('Save profile'), findsOneWidget);

    bed.auth.expire();
    await tester.pumpAndSettle();

    expect(find.text('Save profile'), findsNothing);
    expect(find.byKey(const Key('sign-in-submit')), findsOneWidget);
    expect(find.text('Your session has ended. Please sign in again.'),
        findsOneWidget);
  });
}

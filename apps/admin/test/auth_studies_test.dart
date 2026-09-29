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

    await tester.enterText(find.byKey(const Key('email')), 'staff@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(MessageBanner), findsOneWidget);
    expect(find.text('Invalid email or password'), findsOneWidget);
    expect(find.byKey(const Key('sign-in-submit')), findsOneWidget);
  });

  testWidgets('a participant account is refused by the Research Admin',
      (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    bed.authRepository.role = 'participant';
    await pumpApp(tester, bed, signedIn: false, role: 'participant');

    await tester.enterText(find.byKey(const Key('email')), 'p@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'password1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('not a staff account'), findsOneWidget);
    expect(bed.authRepository.signedOut, isTrue);
  });

  testWidgets('admin lists and creates studies', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    await pumpApp(tester, bed);

    expect(find.text('Face attention pilot'), findsOneWidget);
    expect(find.text('Second study'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-study-name')), 'Third study');
    await tester.tap(find.byKey(const Key('create-study')));
    await tester.pumpAndSettle();

    expect(bed.studies.created, ['Third study']);
    expect(find.text('Third study'), findsOneWidget);
    expect(find.text('Study "Third study" created.'), findsOneWidget);
  });

  testWidgets('a researcher cannot create studies', (tester) async {
    useWindow(tester, 800);
    await pumpApp(tester, TestBed(), role: 'researcher');
    expect(find.byKey(const Key('create-study')), findsNothing);
    expect(find.text('Face attention pilot'), findsOneWidget);
  });

  testWidgets('expired session returns to sign-in from a study screen',
      (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    await openStudy(tester, bed);
    expect(find.text('Participants'), findsWidgets);

    bed.auth.expire();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-submit')), findsOneWidget);
    expect(find.text('Your session has ended. Please sign in again.'),
        findsOneWidget);
  });
}

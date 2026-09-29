import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/erase/application/erase_controller.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openProfile(WidgetTester tester, TestBed bed) async {
  await pumpApp(tester, bed);
  // The home page is a lazy list: scroll until the step has been built.
  final step = find.byKey(const Key('open-profile'));
  await tester.scrollUntilVisible(
    step,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(step);
  await tester.pumpAndSettle();
}

Future<void> openEraseDialog(WidgetTester tester) async {
  final button = find.byKey(const Key('erase-open'));
  await tester.scrollUntilVisible(
    button,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

FilledButton confirmButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('erase-confirm')));

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('erase-phrase')), text);
  await tester.pump();
}

void main() {
  group('the section on the profile screen', () {
    testWidgets('explains what is deleted and that the account closes',
        (tester) async {
      useWindow(tester, 800, 1600);
      await openProfile(tester, TestBed());
      final section = find.byKey(const Key('erase-section'));
      await tester.ensureVisible(section);
      expect(find.text('Withdraw and delete my data'), findsWidgets);
      expect(find.textContaining('You can leave the study at any time'), findsOneWidget);
      for (final part in [
        'your consent',
        'your profile',
        'your sessions',
        'your account is closed',
        'you cannot sign in again',
        'cannot be undone',
        'Download my data',
      ]) {
        expect(find.textContaining(part), findsWidgets, reason: part);
      }
      final button = tester.widget<OutlinedButton>(find.byKey(const Key('erase-open')));
      expect(button.style!.foregroundColor!.resolve({}), AppColors.error);
    });

    testWidgets('opening the dialog changes nothing', (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed();
      await openProfile(tester, bed);
      await openEraseDialog(tester);
      expect(find.text('Delete your data and close your account?'), findsOneWidget);
      expect(find.textContaining('type ${EraseController.phrase} below'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
      expect(bed.erase.confirmations, isEmpty);
    });
  });

  group('the phrase', () {
    testWidgets('must be typed exactly', (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed();
      await openProfile(tester, bed);
      await openEraseDialog(tester);

      for (final wrong in [
        'DELETE MY DAT',
        'delete my data',
        'Delete my data',
        'DELETE  MY DATA',
        'DELETEMYDATA',
        'DELETE MY DATA NOW',
        'yes',
      ]) {
        await type(tester, wrong);
        expect(confirmButton(tester).onPressed, isNull, reason: '"$wrong" is not the phrase');
      }
      await type(tester, 'DELETE MY DATA');
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(bed.erase.confirmations, isEmpty, reason: 'typing alone deletes nothing');
    });

    test('is checked again by the controller', () async {
      final repo = FakeEraseRepository();
      var erased = 0;
      final c = EraseController(repo, onErased: (_) => erased++);
      addTearDown(c.dispose);
      expect(await c.erase('delete my data'), isFalse);
      expect(c.error, contains('DELETE MY DATA'));
      expect(repo.confirmations, isEmpty);
      expect(erased, 0);
      expect(EraseController.matches('  DELETE MY DATA '), isTrue, reason: 'spaces around it are ignored');
      expect(EraseController.matches('DELETE MY DATA'), isTrue);
      expect(EraseController.matches('DELETE MY DATA.'), isFalse);
    });
  });

  group('confirming', () {
    testWidgets('erases, signs out and says goodbye', (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed();
      await openProfile(tester, bed);
      final loadsBefore = bed.home.loads;
      await openEraseDialog(tester);
      await type(tester, 'DELETE MY DATA');
      await tester.tap(find.byKey(const Key('erase-confirm')));
      await tester.pumpAndSettle();

      // POST /me/erase with the phrase.
      expect(bed.erase.confirmations, ['DELETE MY DATA']);
      expect(bed.home.loads, loadsBefore,
          reason: 'nothing is reloaded for an account that no longer exists');
      // Signed out: the sign-in screen with the farewell.
      expect(bed.auth.isSignedIn, isFalse);
      expect(find.text('Sign in'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('auth-notice')),
          matching: find.text('Your data has been deleted and your account is closed. '
              'Thank you for taking part.'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('erase-section')), findsNothing);
    });

    testWidgets('the farewell says what stays when the study keeps coded rows',
        (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed(erase: FakeEraseRepository()..policy = RetentionPolicy.keepCoded);
      await openProfile(tester, bed);
      await openEraseDialog(tester);
      await type(tester, 'DELETE MY DATA');
      await tester.tap(find.byKey(const Key('erase-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('coded research data without your name or email stays'),
          findsOneWidget);
    });

    testWidgets('the farewell can be dismissed', (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed();
      await openProfile(tester, bed);
      await openEraseDialog(tester);
      await type(tester, 'DELETE MY DATA');
      await tester.tap(find.byKey(const Key('erase-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-notice')), findsNothing);
    });

    testWidgets('a refusal keeps the participant signed in and shows why',
        (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed(
        erase: FakeEraseRepository()
          ..failure = const ApiException('Could not reach the server. Check your connection and try again.'),
      );
      await openProfile(tester, bed);
      await openEraseDialog(tester);
      await type(tester, 'DELETE MY DATA');
      await tester.tap(find.byKey(const Key('erase-confirm')));
      await tester.pumpAndSettle();
      expect(bed.auth.isSignedIn, isTrue);
      expect(find.text('Could not reach the server. Check your connection and try again.'),
          findsOneWidget);
      expect(find.byKey(const Key('auth-notice')), findsNothing);
    });

    testWidgets('keeping the data closes the dialog and does nothing',
        (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed();
      await openProfile(tester, bed);
      await openEraseDialog(tester);
      await type(tester, 'DELETE MY DATA');
      await tester.tap(find.byKey(const Key('erase-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Delete your data and close your account?'), findsNothing);
      expect(bed.erase.confirmations, isEmpty);
      expect(bed.auth.isSignedIn, isTrue);
    });
  });

  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('the section and the dialog fit ${width.toInt()} px', (tester) async {
      useWindow(tester, width, width == 360 ? 740 : 900);
      await openProfile(tester, TestBed());
      await openEraseDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('erase-phrase')), findsOneWidget);
    });
  }

  test('the farewell for the default policy', () {
    expect(EraseController.farewell(const EraseResult()),
        startsWith('Your data has been deleted'));
  });
}

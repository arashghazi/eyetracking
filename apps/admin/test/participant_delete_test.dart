import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:research_admin/features/participants/application/participants_controller.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openParticipant(WidgetTester tester, TestBed bed,
    {String role = 'researcher'}) async {
  await openStudy(tester, bed, role: role);
  await tester.tap(find.text('P-001'));
  await tester.pumpAndSettle();
}

Future<void> openDialog(WidgetTester tester) async {
  // The detail is a lazy list: scroll until the button has been built.
  final button = find.byKey(const Key('delete-participant-data'));
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
    tester.widget<FilledButton>(find.byKey(const Key('delete-confirm')));

void main() {
  testWidgets('a red outlined button opens a dialog that names the code',
      (tester) async {
    useWindow(tester, 800, 1600);
    await openParticipant(tester, TestBed());
    final button = find.byKey(const Key('delete-participant-data'));
    await tester.ensureVisible(button);
    expect(find.text("Delete this participant's research data"), findsOneWidget);
    final style = tester.widget<OutlinedButton>(button).style!;
    expect(style.foregroundColor!.resolve({}), AppColors.error);
    expect(style.side!.resolve({})!.color, AppColors.error);

    await openDialog(tester);
    expect(find.text("Delete this participant's research data?"), findsOneWidget);
    expect(find.textContaining('type the research code P-001'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNull, reason: 'nothing typed yet');
  });

  testWidgets('the delete button needs the exact research code', (tester) async {
    useWindow(tester, 800, 1600);
    final bed = TestBed();
    await openParticipant(tester, bed);
    await openDialog(tester);

    Future<void> type(String text) async {
      await tester.enterText(find.byKey(const Key('delete-code-field')), text);
      await tester.pump();
    }

    for (final wrong in ['P-00', 'p-001', 'P-0011', 'P001', 'P-002', 'DELETE']) {
      await type(wrong);
      expect(confirmButton(tester).onPressed, isNull, reason: '"$wrong" is not the code');
    }
    await type('P-001');
    expect(confirmButton(tester).onPressed, isNotNull);
    // Nothing was deleted by typing.
    expect(bed.participants.deletions, isEmpty);
  });

  testWidgets('cancelling deletes nothing', (tester) async {
    useWindow(tester, 800, 1600);
    final bed = TestBed();
    await openParticipant(tester, bed);
    await openDialog(tester);
    await tester.enterText(find.byKey(const Key('delete-code-field')), 'P-001');
    await tester.tap(find.byKey(const Key('delete-cancel')));
    await tester.pumpAndSettle();
    expect(bed.participants.deletions, isEmpty);
    expect(find.text("Delete this participant's research data?"), findsNothing);
  });

  testWidgets('confirming deletes, refreshes the record and shows a banner',
      (tester) async {
    useWindow(tester, 800, 1600);
    final bed = TestBed();
    await openParticipant(tester, bed);
    // Before: consent and profile are there.
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Agreed'), findsOneWidget);

    await openDialog(tester);
    await tester.enterText(find.byKey(const Key('delete-code-field')), 'P-001');
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(bed.participants.deletions, [(code: 'P-001', confirm: 'P-001')]);
    // The banner says what happened.
    expect(
      find.text('The research data of P-001 was deleted (2 sessions, 900 samples). '
          'The account and the research code remain.'),
      findsOneWidget,
    );
    // The detail was refreshed: an empty record.
    expect(find.text('Sam'), findsNothing);
    expect(find.text('Agreed'), findsNothing);
    expect(find.text('No consent recorded'), findsOneWidget);
    expect(find.text('No profile saved'), findsOneWidget);
    expect(find.text('P-001'), findsWidgets, reason: 'the code stays');
  });

  testWidgets('the banner can be dismissed', (tester) async {
    useWindow(tester, 800, 1600);
    await openParticipant(tester, TestBed());
    await openDialog(tester);
    await tester.enterText(find.byKey(const Key('delete-code-field')), 'P-001');
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('was deleted'), findsNothing);
  });

  testWidgets('a refusal from the server is shown and nothing changes',
      (tester) async {
    useWindow(tester, 800, 1600);
    final repo = FakeParticipantsRepository()
      ..deleteFailure = const ApiException('Not a member of this study.', statusCode: 403);
    await openParticipant(tester, TestBed(participants: repo));
    await openDialog(tester);
    await tester.enterText(find.byKey(const Key('delete-code-field')), 'P-001');
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Not a member of this study.'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.textContaining('was deleted'), findsNothing);
  });

  testWidgets('analysts cannot delete', (tester) async {
    useWindow(tester, 800, 1600);
    await openParticipant(tester, TestBed(), role: 'analyst');
    expect(find.byKey(const Key('delete-participant-data'), skipOffstage: false),
        findsNothing);
  });

  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('the dialog fits ${width.toInt()} px', (tester) async {
      useWindow(tester, width, width == 360 ? 740 : 900);
      await openParticipant(tester, TestBed());
      await openDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('delete-code-field')), findsOneWidget);
    });
  }

  test('the controller refuses a wrong code without calling the server', () async {
    // Guards the rule even if a caller skips the dialog.
    final repo = FakeParticipantsRepository();
    final controller = ParticipantDetailController(repo, 1, readyRecord);
    expect(await controller.deleteData('P-01'), isFalse);
    expect(repo.deletions, isEmpty);
    expect(controller.error, contains('P-001'));
    controller.dispose();
  });
}

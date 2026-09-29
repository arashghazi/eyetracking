import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openMembers(WidgetTester tester, TestBed bed) async {
  await openStudy(tester, bed, role: 'admin');
  await openTab(tester, 'Members');
}

void main() {
  testWidgets('an administrator sees the retention policy (default: delete everything)',
      (tester) async {
    useWindow(tester, 800, 1400);
    await openMembers(tester, TestBed());
    expect(find.byKey(const Key('study-settings')), findsOneWidget);
    expect(find.text('Study settings'), findsOneWidget);
    expect(find.text('Delete everything'), findsOneWidget);
    expect(find.textContaining('all of their research rows are deleted too'), findsOneWidget);
    // Nothing to save yet.
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('save-retention-policy'))).onPressed,
      isNull,
    );
  });

  testWidgets('changing the policy saves it with PUT /studies/{id}', (tester) async {
    useWindow(tester, 800, 1400);
    final studies = FakeStudiesRepository();
    await openMembers(tester, TestBed(studies: studies));

    await tester.tap(find.byKey(const Key('retention-policy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep coded research rows').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('the coded research rows stay'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-retention-policy')));
    await tester.pumpAndSettle();

    expect(studies.policyChanges, [(id: 1, policy: 'keep_coded')]);
    expect(find.textContaining('Retention policy saved: keep coded research rows'),
        findsOneWidget);
    expect((await studies.get(1)).retentionPolicy, RetentionPolicy.keepCoded);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('save-retention-policy'))).onPressed,
      isNull,
      reason: 'saved: nothing left to save',
    );
  });

  testWidgets('the saved policy is what the card shows next time', (tester) async {
    useWindow(tester, 800, 1400);
    final studies = FakeStudiesRepository();
    studies.studies[0] =
        studies.studies[0].copyWith(retentionPolicy: RetentionPolicy.keepCoded);
    await openMembers(tester, TestBed(studies: studies));
    expect(find.text('Keep coded research rows'), findsOneWidget);
  });

  testWidgets('a refusal is shown and the policy stays', (tester) async {
    useWindow(tester, 800, 1400);
    final studies = FakeStudiesRepository()
      ..policyFailure =
          const ApiException('You do not have permission to do this.', statusCode: 403);
    await openMembers(tester, TestBed(studies: studies));
    await tester.tap(find.byKey(const Key('retention-policy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep coded research rows').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-retention-policy')));
    await tester.pumpAndSettle();
    expect(find.text('You do not have permission to do this.'), findsOneWidget);
    expect((await studies.get(1)).retentionPolicy, RetentionPolicy.deleteAll);
  });

  testWidgets('an administrator who is not a member can still set the policy',
      (tester) async {
    useWindow(tester, 800, 1400);
    final studies = FakeStudiesRepository()
      ..getFailure = const ApiException('no access to this study', statusCode: 403);
    await openMembers(tester, TestBed(studies: studies));

    // The current policy cannot be read: say so, and show no policy as chosen.
    expect(find.byKey(const Key('retention-unreadable')), findsOneWidget);
    expect(find.text('Choose a policy'), findsOneWidget);
    expect(find.text('no access to this study'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('save-retention-policy'))).onPressed,
      isNull,
      reason: 'nothing chosen yet',
    );

    await tester.tap(find.byKey(const Key('retention-policy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everything').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-retention-policy')));
    await tester.pumpAndSettle();

    expect(studies.policyChanges, [(id: 1, policy: 'delete_all')]);
    expect(find.textContaining('Retention policy saved: delete everything'), findsOneWidget);
    expect(find.byKey(const Key('retention-unreadable')), findsNothing);
  });

  testWidgets('another failure to read the study is shown with a retry',
      (tester) async {
    useWindow(tester, 800, 1400);
    final studies = FakeStudiesRepository()
      ..getFailure = const ApiException('Something broke.', statusCode: 500);
    await openMembers(tester, TestBed(studies: studies));
    expect(find.text('Something broke.'), findsOneWidget);
    expect(find.byKey(const Key('retry-study-settings')), findsOneWidget);
    studies.getFailure = null;
    await tester.tap(find.byKey(const Key('retry-study-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Delete everything'), findsOneWidget);
  });

  testWidgets('researchers never see it (the Members tab is admin only)',
      (tester) async {
    useWindow(tester, 800, 1400);
    await openStudy(tester, TestBed(), role: 'researcher');
    expect(find.widgetWithText(Tab, 'Members'), findsNothing);
    expect(find.byKey(const Key('study-settings'), skipOffstage: false), findsNothing);
  });

  for (final width in [360.0, 1440.0]) {
    testWidgets('the card fits ${width.toInt()} px', (tester) async {
      useWindow(tester, width, width == 360 ? 740 : 900);
      await openMembers(tester, TestBed());
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('study-settings')), findsOneWidget);
    });
  }
}

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('a missing required field blocks submit', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed(home: FakeHomeRepository(reasons: const [
      ReadinessReason.demographicsIncomplete,
    ]));
    await pumpApp(tester, bed);
    await openStep(tester, 'demographics');

    expect(find.text('Age in years *'), findsOneWidget);
    expect(find.text('Gender'), findsOneWidget);
    expect(find.text('I wear glasses'), findsOneWidget);

    await tester.tap(find.byKey(const Key('demographics-submit')));
    await tester.pumpAndSettle();
    expect(find.text('This field is required.'), findsOneWidget);
    expect(bed.demographics.saved, isEmpty);

    // A non-numeric value is rejected on a number field as well.
    await tester.enterText(find.byKey(const Key('field-age')), '-');
    await tester.tap(find.byKey(const Key('demographics-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a number.'), findsOneWidget);
    expect(bed.demographics.saved, isEmpty);
  });

  testWidgets('valid answers are saved with API types', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await pumpApp(tester, bed);
    await openStep(tester, 'demographics');

    await tester.enterText(find.byKey(const Key('field-age')), '34');
    await tester.tap(find.byKey(const Key('field-gender')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Woman').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('field-glasses')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('demographics-submit')));
    await tester.pumpAndSettle();

    expect(bed.demographics.saved, [
      {'age': 34, 'gender': 'Woman', 'glasses': true},
    ]);
    expect(find.text('Your answers have been saved.'), findsOneWidget);
  });

  testWidgets('saved answers are prefilled', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed(
      demographics: FakeDemographicsRepository(
        form: sampleForm,
        answers: const DemographicsAnswers(
          formVersion: 2,
          answers: {'age': 41, 'notes': 'None'},
        ),
      ),
    );
    await pumpApp(tester, bed);
    await openStep(tester, 'demographics');

    expect(find.widgetWithText(TextField, '41'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'None'), findsOneWidget);
  });

  testWidgets('no form published is explained', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed(demographics: FakeDemographicsRepository());
    await pumpApp(tester, bed);
    await openStep(tester, 'demographics');
    expect(find.text('There are no demographics questions yet.'), findsOneWidget);
  });
}

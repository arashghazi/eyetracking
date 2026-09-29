import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('build a form with a choice field and publish it', (tester) async {
    useWindow(tester, 800, 1800);
    final bed = TestBed();
    await openStudy(tester, bed);
    await openTab(tester, 'Demographics form');

    expect(find.textContaining('No demographics form has been published'),
        findsOneWidget);

    // First field: number, required.
    await tester.tap(find.byKey(const Key('add-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('key-1')), 'age');
    await tester.enterText(find.byKey(const ValueKey('label-1')), 'Age in years');
    await tester.tap(find.byKey(const ValueKey('type-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('required-1')));
    await tester.pumpAndSettle();

    // Second field: choice with comma-separated options.
    await tapVisible(tester, find.byKey(const Key('add-field')));
    await tester.enterText(find.byKey(const ValueKey('key-2')), 'gender');
    await tester.enterText(find.byKey(const ValueKey('label-2')), 'Gender');
    await tester.tap(find.byKey(const ValueKey('type-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choice').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('options-2')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('options-2')),
      'Woman, Man ,  Another description',
    );

    await tapVisible(tester, find.byKey(const Key('publish-form')));
    expect(find.text('Publish a new version?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('form-publish-confirm')));
    await tester.pumpAndSettle();

    expect(bed.demographicsForm.published.single, [
      {'key': 'age', 'label': 'Age in years', 'type': 'number', 'required': true},
      {
        'key': 'gender',
        'label': 'Gender',
        'type': 'choice',
        'options': ['Woman', 'Man', 'Another description'],
        'required': false,
      },
    ]);
    expect(find.text('Version 1 is now published.'), findsOneWidget);
  });

  testWidgets('invalid rows are flagged and nothing is sent', (tester) async {
    useWindow(tester, 800, 1800);
    final bed = TestBed(
      demographicsForm: FakeDemographicsFormRepository(
        form: const DemographicsForm(version: 3, fields: [
          DemographicsField(
            key: 'age',
            label: 'Age',
            type: DemographicsFieldType.number,
          ),
        ]),
      ),
    );
    await openStudy(tester, bed);
    await openTab(tester, 'Demographics form');
    expect(find.textContaining('Current version: 3'), findsOneWidget);

    // A second row with a duplicate key.
    await tester.tap(find.byKey(const Key('add-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('key-2')), 'age');
    await tapVisible(tester, find.byKey(const Key('publish-form')));

    expect(find.text('Key "age" is used more than once.'), findsOneWidget);
    expect(find.text('Please fix the highlighted fields before publishing.'),
        findsOneWidget);
    expect(bed.demographicsForm.published, isEmpty);

    // Removing the offending row lets the publish through.
    await tapVisible(tester, find.byKey(const ValueKey('remove-2')));
    await tapVisible(tester, find.byKey(const Key('publish-form')));
    await tester.tap(find.byKey(const Key('form-publish-confirm')));
    await tester.pumpAndSettle();
    expect(bed.demographicsForm.published, hasLength(1));
    expect(find.textContaining('Current version: 4'), findsOneWidget);
  });

  testWidgets('a choice field without options is rejected', (tester) async {
    useWindow(tester, 800, 1800);
    final bed = TestBed();
    await openStudy(tester, bed);
    await openTab(tester, 'Demographics form');

    await tester.tap(find.byKey(const Key('add-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('key-1')), 'gender');
    await tester.tap(find.byKey(const ValueKey('type-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choice').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('publish-form')));

    expect(find.text('A choice field needs at least one option.'), findsOneWidget);
    expect(bed.demographicsForm.published, isEmpty);
  });

  testWidgets('fields can be reordered', (tester) async {
    useWindow(tester, 800, 1800);
    final bed = TestBed(
      demographicsForm: FakeDemographicsFormRepository(
        form: const DemographicsForm(version: 1, fields: [
          DemographicsField(key: 'a', label: 'A', type: DemographicsFieldType.text),
          DemographicsField(key: 'b', label: 'B', type: DemographicsFieldType.text),
        ]),
      ),
    );
    await openStudy(tester, bed);
    await openTab(tester, 'Demographics form');

    await tester.tap(find.byTooltip('Move down').first);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('publish-form')));
    await tester.tap(find.byKey(const Key('form-publish-confirm')));
    await tester.pumpAndSettle();

    expect(
      [for (final f in bed.demographicsForm.published.single) f['key']],
      ['b', 'a'],
    );
  });
}

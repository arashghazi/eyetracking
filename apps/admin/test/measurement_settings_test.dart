import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openSettings(WidgetTester tester, TestBed bed,
    {String role = 'researcher'}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Measurement settings');
}

Future<void> typeInto(WidgetTester tester, String field, String text) async {
  final finder = find.byKey(Key('setting-$field'));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

/// Presses Save and, when the rationale dialog opens, confirms it with
/// [rationale] (nothing typed when null). An invalid form opens no dialog.
Future<void> saveSettings(WidgetTester tester, {String? rationale}) async {
  await tapVisible(tester, find.byKey(const Key('save-settings')));
  if (find.byKey(const Key('settings-rationale-dialog')).evaluate().isEmpty) {
    return;
  }
  if (rationale != null) {
    await tester.enterText(find.byKey(const Key('settings-rationale')), rationale);
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('settings-rationale-confirm')));
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String field) =>
    tester.widget<TextField>(find.byKey(Key('setting-$field'))).controller!.text;

void main() {
  testWidgets('shows the current values of the six settings', (tester) async {
    useWindow(tester, 800, 1200);
    await openSettings(tester, TestBed());

    expect(textOf(tester, 'validation_min_correct'), '0.8');
    expect(textOf(tester, 'validation_max_uncertain'), '0.2');
    expect(textOf(tester, 'min_region_to_error_ratio'), '2.0');
    expect(textOf(tester, 'gaze_conf_threshold'), '0.5');
    expect(textOf(tester, 'calibration_points'), '9');
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('setting-allow_continue_without_validation')))
          .value,
      isTrue,
    );
    expect(find.byKey(const Key('save-settings')), findsOneWidget);
    expect(find.byKey(const Key('settings-read-only')), findsNothing);
  });

  testWidgets('rejects out-of-range and non-numeric values without saving',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openSettings(tester, bed);

    await typeInto(tester, 'validation_min_correct', '1.5');
    await typeInto(tester, 'validation_max_uncertain', '-0.1');
    await typeInto(tester, 'min_region_to_error_ratio', '0.5');
    await typeInto(tester, 'gaze_conf_threshold', 'high');
    await typeInto(tester, 'calibration_points', '4');
    await saveSettings(tester);

    expect(bed.measurementSettings.saved, isEmpty);
    expect(find.byKey(const Key('settings-rationale-dialog')), findsNothing,
        reason: 'an invalid form is not sent, so nothing is asked');
    expect(find.text('Enter a value from 0 to 1.'), findsNWidgets(2));
    expect(find.text('Enter a value of 1 or more.'), findsOneWidget);
    expect(find.text('Enter a number.'), findsOneWidget);
    expect(find.text('Enter a whole number from 5 to 16.'), findsOneWidget);
    expect(find.textContaining('Some values are not valid'), findsOneWidget);
  });

  testWidgets('calibration points must be a whole number from 5 to 16',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openSettings(tester, bed);

    for (final (input, message) in [
      ('4', 'Enter a whole number from 5 to 16.'),
      ('17', 'Enter a whole number from 5 to 16.'),
      ('8.5', 'Enter a whole number.'),
    ]) {
      await typeInto(tester, 'calibration_points', input);
      await saveSettings(tester);
      expect(find.text(message), findsOneWidget, reason: 'for $input');
    }
    expect(bed.measurementSettings.saved, isEmpty);

    for (final ok in ['5', '16']) {
      await typeInto(tester, 'calibration_points', ok);
      await saveSettings(tester);
    }
    expect(bed.measurementSettings.saved.map((s) => s.calibrationPoints), [5, 16]);
  });

  testWidgets('the ratio may be 1 or more, and 0 and 1 are valid shares',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openSettings(tester, bed);

    await typeInto(tester, 'min_region_to_error_ratio', '1');
    await typeInto(tester, 'validation_min_correct', '0');
    await typeInto(tester, 'validation_max_uncertain', '1');
    await saveSettings(tester);

    final saved = bed.measurementSettings.saved.single;
    expect(saved.minRegionToErrorRatio, 1);
    expect(saved.validationMinCorrect, 0);
    expect(saved.validationMaxUncertain, 1);
  });

  testWidgets('Save sends the edited values and confirms', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openSettings(tester, bed);

    await typeInto(tester, 'validation_min_correct', '0,75');
    await typeInto(tester, 'min_region_to_error_ratio', '2.5');
    await typeInto(tester, 'calibration_points', '12');
    await tapVisible(
      tester,
      find.byKey(const Key('setting-allow_continue_without_validation')),
    );
    await saveSettings(tester);

    final saved = bed.measurementSettings.saved.single;
    expect(saved.validationMinCorrect, 0.75);
    expect(saved.validationMaxUncertain, 0.2);
    expect(saved.minRegionToErrorRatio, 2.5);
    expect(saved.gazeConfThreshold, 0.5);
    expect(saved.calibrationPoints, 12);
    expect(saved.allowContinueWithoutValidation, isFalse);
    expect(find.text('Measurement settings saved.'), findsOneWidget);
    expect(find.text('Enter a value from 0 to 1.'), findsNothing);
  });

  testWidgets('a server refusal is shown and nothing claims success',
      (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    bed.measurementSettings.saveFailure =
        const ApiException('Only researchers can change this.', statusCode: 403);
    await openSettings(tester, bed);

    await saveSettings(tester);
    expect(find.text('Only researchers can change this.'), findsOneWidget);
    expect(find.text('Measurement settings saved.'), findsNothing);
  });

  testWidgets('analysts see the settings read-only', (tester) async {
    useWindow(tester, 800, 1400);
    final bed = TestBed();
    await openSettings(tester, bed, role: 'analyst');

    expect(find.byKey(const Key('settings-read-only')), findsOneWidget);
    expect(find.byKey(const Key('save-settings')), findsNothing);
    expect(textOf(tester, 'calibration_points'), '9');
    final field = tester.widget<TextField>(
        find.byKey(const Key('setting-calibration_points')));
    expect(field.enabled, isFalse);
    final switchTile = tester.widget<SwitchListTile>(
        find.byKey(const Key('setting-allow_continue_without_validation')));
    expect(switchTile.onChanged, isNull);
  });

  group('versions and rationale', () {
    testWidgets('shows the settings version', (tester) async {
      useWindow(tester, 800, 1200);
      final bed = TestBed();
      bed.measurementSettings.settings = const MeasurementSettings(version: 4);
      await openSettings(tester, bed);
      expect(find.text('Version 4'), findsOneWidget);
    });

    testWidgets('saving asks for an optional rationale and sends it',
        (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed();
      await openSettings(tester, bed);

      await typeInto(tester, 'validation_min_correct', '0.7');
      await saveSettings(tester, rationale: '  Pilot showed too many fails.  ');

      expect(bed.measurementSettings.saved.single.validationMinCorrect, 0.7);
      expect(bed.measurementSettings.rationales, ['Pilot showed too many fails.']);
      expect(find.text('Version 2'), findsOneWidget,
          reason: 'a real change is a new version');
    });

    testWidgets('the rationale may be left empty', (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed();
      await openSettings(tester, bed);

      await typeInto(tester, 'validation_min_correct', '0.7');
      await saveSettings(tester);

      expect(bed.measurementSettings.saved, hasLength(1));
      expect(bed.measurementSettings.rationales.single, '',
          reason: 'an empty rationale is not a reason to refuse');
    });

    testWidgets('cancelling the dialog saves nothing', (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed();
      await openSettings(tester, bed);

      await typeInto(tester, 'validation_min_correct', '0.7');
      await tapVisible(tester, find.byKey(const Key('save-settings')));
      expect(find.byKey(const Key('settings-rationale-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-rationale-cancel')));
      await tester.pumpAndSettle();

      expect(bed.measurementSettings.saved, isEmpty);
      expect(find.byKey(const Key('settings-rationale-dialog')), findsNothing);
    });

    testWidgets('the history button shows the versions and refreshes after a save',
        (tester) async {
      useWindow(tester, 800, 1600);
      final bed = TestBed();
      await openSettings(tester, bed);
      expect(find.byKey(const Key('history-list')), findsNothing);

      await tapVisible(tester, find.byKey(const Key('settings-history-toggle')));
      expect(find.byKey(const Key('history-list')), findsOneWidget);
      expect(find.text('Version 1'), findsWidgets);

      await typeInto(tester, 'validation_min_correct', '0.7');
      await saveSettings(tester, rationale: 'Loosened for the pilot');
      expect(find.text('Loosened for the pilot'), findsOneWidget);
      expect(find.byKey(const Key('history-2-validation_min_correct')), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('settings-history-toggle')));
      expect(find.byKey(const Key('history-list')), findsNothing);
    });

    testWidgets('analysts can read the history but not save', (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed();
      await openSettings(tester, bed, role: 'analyst');
      expect(find.byKey(const Key('save-settings')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('settings-history-toggle')));
      expect(find.byKey(const Key('history-list')), findsOneWidget);
    });

    testWidgets('a new version saved elsewhere shows when the tab returns',
        (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed();
      await openSettings(tester, bed);
      expect(textOf(tester, 'validation_min_correct'), '0.8');

      // A threshold review saved version 2 from the Pilot tab.
      bed.measurementSettings.settings = const MeasurementSettings(
        validationMinCorrect: 0.7,
        version: 2,
      );
      await openTab(tester, 'Pilot');
      await openTab(tester, 'Measurement settings');

      expect(textOf(tester, 'validation_min_correct'), '0.7');
      expect(find.text('Version 2'), findsOneWidget);
    });

    testWidgets('unsaved edits are not overwritten when the tab returns',
        (tester) async {
      useWindow(tester, 800, 1400);
      final bed = TestBed();
      await openSettings(tester, bed);
      await typeInto(tester, 'validation_min_correct', '0.65');

      bed.measurementSettings.settings = const MeasurementSettings(
        validationMinCorrect: 0.7,
        version: 2,
      );
      await openTab(tester, 'Pilot');
      await openTab(tester, 'Measurement settings');

      expect(textOf(tester, 'validation_min_correct'), '0.65');
    });
  });

  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('renders without overflow at ${width.toInt()} px',
        (tester) async {
      useWindow(tester, width, width == 360 ? 740 : 900);
      await openSettings(tester, TestBed());
      expect(find.byKey(const Key('setting-calibration_points')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

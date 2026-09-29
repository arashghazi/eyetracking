import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('study screen renders every tab at ${width.toInt()} px',
        (tester) async {
      useWindow(tester, width, width == 360 ? 740 : 900);
      final bed = TestBed(
        informationSheet: FakeInformationSheetRepository(
          sheet: const InformationSheet(
            version: 2,
            content: SheetContent(
              aims: 'Aims',
              discomfortSources: 'Discomfort',
              benefits: 'Benefits',
              dataHandling: 'Data',
              stopRules: 'Stop',
            ),
          ),
        ),
        demographicsForm: FakeDemographicsFormRepository(
          form: const DemographicsForm(version: 1, fields: [
            DemographicsField(
              key: 'gender',
              label: 'Gender',
              type: DemographicsFieldType.choice,
              options: ['Woman', 'Man'],
              required: true,
            ),
          ]),
        ),
      );
      await openStudy(tester, bed);

      // Participants tab (default).
      expect(find.byType(DataTable), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final tab in [
        'Sessions',
        'Protocols',
        'Content',
        'Invitations',
        'Information sheet',
        'Demographics form',
        'Measurement settings',
        'Members',
      ]) {
        await openTab(tester, tab);
        expect(tester.takeException(), isNull, reason: '$tab tab overflowed');
      }
    });
  }

  testWidgets('Members tab is only offered to administrators', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed();
    await openStudy(tester, bed, role: 'researcher');
    expect(find.widgetWithText(Tab, 'Participants'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Sessions'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Protocols'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Content'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Invitations'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Measurement settings'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Members'), findsNothing);
  });
}

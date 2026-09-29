import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

FilledButton publishButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('publish-sheet')));

void main() {
  testWidgets('publish needs all five sections and confirms the new version',
      (tester) async {
    useWindow(tester, 800, 1800);
    final bed = TestBed();
    await openStudy(tester, bed);
    await openTab(tester, 'Information sheet');

    expect(find.textContaining('No information sheet has been published'),
        findsOneWidget);
    expect(publishButton(tester).onPressed, isNull);

    Future<void> fill(String key, String text) async {
      await tester.enterText(find.byKey(Key(key)), text);
      await tester.pump();
    }

    await fill('sheet-aims', 'Aims text');
    await fill('sheet-discomfort', 'Discomfort text');
    await fill('sheet-benefits', 'Benefits text');
    await fill('sheet-data', 'Data text');
    expect(publishButton(tester).onPressed, isNull, reason: 'one section missing');
    await fill('sheet-stop', 'Stop text');
    expect(publishButton(tester).onPressed, isNotNull);

    await tapVisible(tester, find.byKey(const Key('publish-sheet')));
    expect(find.text('Publish a new version?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('publish-confirm')));
    await tester.pumpAndSettle();

    expect(bed.informationSheet.published.single.aims, 'Aims text');
    expect(bed.informationSheet.published.single.stopRules, 'Stop text');
    expect(find.textContaining('Current version: 1'), findsOneWidget);
    expect(find.text('Version 1 is now published.'), findsOneWidget);
  });

  testWidgets('existing sheet is loaded and publishing makes the next version',
      (tester) async {
    useWindow(tester, 800, 1800);
    final bed = TestBed(
      informationSheet: FakeInformationSheetRepository(
        sheet: const InformationSheet(
          version: 4,
          publishedAt: '2026-09-01T10:00:00Z',
          content: SheetContent(
            aims: 'Old aims',
            discomfortSources: 'Old discomfort',
            benefits: 'Old benefits',
            dataHandling: 'Old data',
            stopRules: 'Old stop',
          ),
        ),
      ),
    );
    await openStudy(tester, bed);
    await openTab(tester, 'Information sheet');

    expect(find.textContaining('Current version: 4'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Old aims'), findsOneWidget);
    expect(publishButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('sheet-aims')), 'New aims');
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('publish-sheet')));
    expect(find.textContaining('publishes version 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('publish-confirm')));
    await tester.pumpAndSettle();

    expect(bed.informationSheet.published.single.aims, 'New aims');
    expect(find.textContaining('Current version: 5'), findsOneWidget);
  });

  testWidgets('cancelling the dialog publishes nothing', (tester) async {
    useWindow(tester, 800, 1800);
    final bed = TestBed(
      informationSheet: FakeInformationSheetRepository(
        sheet: const InformationSheet(
          version: 1,
          content: SheetContent(
            aims: 'a',
            discomfortSources: 'b',
            benefits: 'c',
            dataHandling: 'd',
            stopRules: 'e',
          ),
        ),
      ),
    );
    await openStudy(tester, bed);
    await openTab(tester, 'Information sheet');
    await tapVisible(tester, find.byKey(const Key('publish-sheet')));
    await tester.tap(find.byKey(const Key('publish-cancel')));
    await tester.pumpAndSettle();
    expect(bed.informationSheet.published, isEmpty);
  });
}

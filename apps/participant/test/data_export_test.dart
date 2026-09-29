import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/data_export/application/data_export_controller.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openDownload(WidgetTester tester, TestBed bed) async {
  await pumpApp(tester, bed);
  final button = find.byKey(const Key('download-data'));
  await tester.scrollUntilVisible(
    button,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

String countOf(WidgetTester tester, String key) => tester
    .widget<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)).first)
    .data!;

void main() {
  group('the counts', () {
    testWidgets('sessions, samples, events and consents are shown', (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed();
      await openDownload(tester, bed);

      expect(bed.dataExport.fetches, 1);
      expect(countOf(tester, 'count-sessions'), '2');
      expect(countOf(tester, 'count-samples'), '8');
      expect(countOf(tester, 'count-events'), '3');
      expect(countOf(tester, 'count-consents'), '2');
      for (final label in ['Sessions', 'Gaze samples', 'Session events', 'Consents']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('say that the numbers are the raw data and no video exists',
        (tester) async {
      useWindow(tester, 800, 1000);
      await openDownload(tester, TestBed());
      final note = find.byKey(const Key('raw-data-note'));
      expect(find.descendant(of: note, matching: find.textContaining('gaze numbers and the session events are the raw data')),
          findsOneWidget);
      expect(find.descendant(of: note, matching: find.textContaining('No camera video exists')),
          findsOneWidget);
    });

    testWidgets('an account without any session shows zeros', (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed(
        dataExport: FakeDataExportRepository(data: {'participant': {'code': 'P-1'}}),
      );
      await openDownload(tester, bed);
      expect(countOf(tester, 'count-sessions'), '0');
      expect(countOf(tester, 'count-samples'), '0');
      expect(countOf(tester, 'count-consents'), '0');
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('fits ${width.toInt()} px', (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        await openDownload(tester, TestBed());
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('download-json')), findsOneWidget);
        expect(find.byKey(const Key('count-samples')), findsOneWidget);
      });
    }
  });

  group('Download JSON', () {
    testWidgets('saves the data as a JSON file', (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed();
      await openDownload(tester, bed);
      await tester.tap(find.byKey(const Key('download-json')));
      await tester.pumpAndSettle();

      final file = bed.saver.saved.single;
      expect(file.name, 'my-eyetracking-data.json');
      expect(file.type, 'application/json');
      // The file is the data, unchanged.
      expect(jsonDecode(utf8.decode(file.bytes)), bed.dataExport.data);
      expect(find.text('Your data was downloaded as my-eyetracking-data.json.'),
          findsOneWidget);
    });

    testWidgets('outside the browser it says the download is not available',
        (tester) async {
      useWindow(tester, 800, 1000);
      final bed = TestBed(canSaveFiles: false);
      await openDownload(tester, bed);
      await tester.tap(find.byKey(const Key('download-json')));
      await tester.pumpAndSettle();
      expect(find.text('Downloads are available in the web app.'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry and no download', (tester) async {
      useWindow(tester, 800, 1000);
      final repo = FakeDataExportRepository()
        ..failure = const ApiException('Could not reach the server. Check your connection and try again.');
      final bed = TestBed(dataExport: repo);
      await openDownload(tester, bed);
      expect(find.text('Could not reach the server. Check your connection and try again.'),
          findsOneWidget);
      expect(find.byKey(const Key('download-json')), findsNothing);
      repo.failure = null;
      await tester.tap(find.byKey(const Key('reload-data')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('download-json')), findsOneWidget);
    });
  });

  group('the file', () {
    test('is readable: each gaze sample on one line', () {
      final text = prettyJson({
        'participant': {'code': 'P-1'},
        'sessions': [
          {
            'samples': [
              [0, 1.5, 2.5, 0.9, 2],
              [100, null, null, 0.1, 4],
            ],
            'tags': ['a', 'b'],
            'empty': [],
            'none': {},
          },
        ],
      });
      expect(text, contains('"participant": {\n    "code": "P-1"\n  }'));
      expect(text, contains('        [0,1.5,2.5,0.9,2],\n        [100,null,null,0.1,4]'));
      expect(text, contains('"tags": ["a","b"]'));
      expect(text, contains('"empty": []'));
      expect(text, contains('"none": {}'));
      // And it is valid JSON that says the same.
      expect(jsonDecode(text), isA<Map>());
    });

    test('keeps the data unchanged through a round trip', () {
      final again = jsonDecode(prettyJson(sampleMyData));
      expect(again, sampleMyData);
    });

    test('the controller does not offer a file before the data is loaded',
        () async {
      final c = DataExportController(FakeDataExportRepository(), RecordingFileSaver().call);
      addTearDown(c.dispose);
      expect(c.fileBytes(), isNull);
      expect(await c.download(), isFalse);
      await c.load();
      expect(c.fileBytes(), isNotNull);
      expect(c.counts!.samples, 8);
    });
  });
}

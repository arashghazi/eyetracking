import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/content/domain/media_picker.dart';
import 'package:research_admin/features/pilot/presentation/pilot_widgets.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'pilot_fixtures.dart';

Finder key(String k) => find.byKey(Key(k), skipOffstage: false);

Future<void> openPilot(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Pilot');
}

Future<void> section(WidgetTester tester, String name) =>
    tapVisible(tester, key('pilot-section-$name'));

Future<void> tapKey(WidgetTester tester, String k) => tapVisible(tester, key(k));

Future<void> typeInto(WidgetTester tester, String k, String text) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.enterText(key(k), text);
  await tester.pump();
}

/// Picks [label] in the dropdown [k].
Future<void> choose(WidgetTester tester, String k, String label) async {
  await tapKey(tester, k);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The value of a `StatTile`, `FactRow` or `ShareBar`: the second Text in it
/// (after the label).
String valueOf(WidgetTester tester, String k) {
  final texts = tester
      .widgetList<Text>(find.descendant(of: key(k), matching: find.byType(Text)))
      .toList();
  return texts[1].data ?? texts[1].textSpan!.toPlainText();
}

String textOf(WidgetTester tester, String k) {
  final w = tester.widget<Text>(key(k));
  return w.data ?? w.textSpan!.toPlainText();
}

String fieldText(WidgetTester tester, String k) =>
    tester.state<FormFieldState<String>>(key(k)).value ?? '';

/// The strings a table cell shows. Table rows are not in the widget tree (a
/// `DataRow` is data), so cells are read from the `DataTable` widget; only
/// text, layout and `CodeText` are walked.
List<String> cellStrings(Widget w) {
  if (w is Text) return [w.data ?? w.textSpan?.toPlainText() ?? ''];
  if (w is CodeText) return [w.code];
  if (w is SingleChildRenderObjectWidget && w.child != null) {
    return cellStrings(w.child!);
  }
  if (w is MultiChildRenderObjectWidget) {
    return [for (final c in w.children) ...cellStrings(c)];
  }
  if (w is ProxyWidget) return cellStrings(w.child);
  return const [];
}

/// The row of the `DataTable` [table] whose key is [rowKey].
DataRow dataRow(WidgetTester tester, String table, String rowKey) => tester
    .widget<DataTable>(key(table))
    .rows
    .firstWhere((r) => r.key == ValueKey(rowKey),
        orElse: () => throw StateError('no row $rowKey in $table'));

List<String> rowStrings(DataRow row) =>
    [for (final c in row.cells) ...cellStrings(c.child)];

bool hasRow(WidgetTester tester, String table, String rowKey) => tester
    .widget<DataTable>(key(table))
    .rows
    .any((r) => r.key == ValueKey(rowKey));

/// The polling timers that are still armed.
List<ManualTimer> armed(TestBed bed) =>
    [for (final t in bed.timers) if (t.isActive) t];

Future<void> fire(WidgetTester tester, ManualTimer timer) async {
  timer.fire();
  await tester.pumpAndSettle();
}

TestBed liveBed({
  List<LiveStatus>? queue,
  Map<String, List<Observation>>? observations,
}) {
  final bed = TestBed();
  bed.pilot
    ..active = activeSessions
    ..liveQueue = queue ?? [liveStatus()];
  if (observations != null) bed.pilot.observationsBySession.addAll(observations);
  return bed;
}

void main() {
  group('Pilot tab', () {
    testWidgets('sits right after Sessions and opens on Live', (tester) async {
      useWindow(tester, 1440, 1000);
      await openStudy(tester, TestBed());

      final labels = [
        for (final t in tester.widgetList<Tab>(find.byType(Tab))) t.text,
      ];
      expect(labels.sublist(0, 4), ['Participants', 'Sessions', 'Pilot', 'Analysis']);
      expect(labels.indexOf('AI'), 6);

      await openTab(tester, 'Pilot');
      expect(key('section-live'), findsOneWidget);
      for (final name in ['live', 'thresholds', 'tracker', 'report', 'debrief']) {
        expect(key('pilot-section-$name'), findsOneWidget);
      }
    });

    testWidgets('the section switcher shows one part at a time', (tester) async {
      useWindow(tester, 1440, 2000);
      await openPilot(tester, TestBed());

      for (final (name, marker) in [
        ('thresholds', 'section-thresholds'),
        ('tracker', 'section-tracker'),
        ('report', 'section-report'),
        ('debrief', 'section-debrief'),
        ('live', 'section-live'),
      ]) {
        await section(tester, name);
        expect(key(marker), findsOneWidget, reason: name);
        for (final other in [
          'section-live',
          'section-thresholds',
          'section-tracker',
          'section-report',
          'section-debrief',
        ]) {
          if (other != marker) expect(key(other), findsNothing, reason: '$name / $other');
        }
      }
    });
  });

  group('Live', () {
    testWidgets('lists the running sessions and Refresh reads them again',
        (tester) async {
      useWindow(tester, 1440, 1600);
      final bed = liveBed();
      await openPilot(tester, bed);

      expect(bed.pilot.activeReads, 1);
      expect(key('active-21'), findsOneWidget);
      expect(find.text('P-001'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Last event: segment_start at 00:01.500'), findsOneWidget);
      expect(find.text('No event yet'), findsOneWidget);
      expect(key('live-panel'), findsNothing);
      expect(bed.pilot.liveCalls, isEmpty, reason: 'nothing is watched yet');

      bed.pilot.active = [activeSessions.first];
      await tapKey(tester, 'live-refresh');
      expect(bed.pilot.activeReads, 2);
      expect(key('active-22'), findsNothing);
    });

    testWidgets('an empty list says so', (tester) async {
      useWindow(tester, 1440, 1000);
      await openPilot(tester, TestBed());
      expect(find.textContaining('No session is running right now'), findsOneWidget);
    });

    testWidgets('an unreadable list shows the server message (admin not a member)',
        (tester) async {
      useWindow(tester, 1440, 1000);
      final bed = TestBed();
      bed.pilot.activeFailure = const ApiException(
        'You are not a member of this study.',
        statusCode: 403,
      );
      await openPilot(tester, bed, role: 'admin');
      expect(find.text('You are not a member of this study.'), findsOneWidget);
    });

    testWidgets('picking a session reads it with first=true, then polls every 2.5 s',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = liveBed(queue: [
        liveStatus(),
        liveStatus(observations: 1),
        liveStatus(observations: 2),
      ]);
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      expect(bed.pilot.liveCalls, [(sessionId: '21', first: true)]);
      expect(key('live-panel'), findsOneWidget);
      expect(textOf(tester, 'live-polling-note'), contains('every 2.5 s'));
      final first = armed(bed).single;
      expect(first.duration, const Duration(milliseconds: 2500));

      await fire(tester, first);
      await fire(tester, armed(bed).single);
      expect(
        bed.pilot.liveCalls.map((c) => c.first).toList(),
        [true, false, false],
        reason: 'first=true only on the first read',
      );
      expect(valueOf(tester, 'live-fact-observations'), '2');
      expect(armed(bed), hasLength(1), reason: 'one read scheduled at a time');
    });

    testWidgets('shows status, segment, pauses, stage, decision, comfort and calibration',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = liveBed(queue: [liveStatus(paused: true)]);
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      expect(textOf(tester, 'live-status'), 'In progress');
      expect(valueOf(tester, 'live-fact-segment'), 'Practice');
      expect(valueOf(tester, 'live-fact-paused'), 'Yes');
      expect(valueOf(tester, 'live-fact-pauses'), '2');
      expect(valueOf(tester, 'live-fact-stage'), '1');
      expect(valueOf(tester, 'live-fact-decision'), 'Stage 0: advance (all_good)');
      expect(valueOf(tester, 'live-fact-comfort'), '4, correct 90 %');
      expect(valueOf(tester, 'live-fact-calibration'), 'Valid');
      expect(valueOf(tester, 'live-fact-validation'), 'Passed');
      expect(valueOf(tester, 'live-fact-estimator'), 'l2cs-net');
      expect(valueOf(tester, 'live-fact-samples'), '480, last at 01:01.250');
      expect(valueOf(tester, 'live-fact-since-event'), '3.5 s ago');
      expect(key('live-synthetic-warning'), findsNothing);
    });

    testWidgets('recent valid share and region counts are small bars', (tester) async {
      useWindow(tester, 1440, 2600);
      await openPilot(tester, liveBed());
      await tapKey(tester, 'monitor-21');

      expect(find.text('Last 10 s of gaze data (40 samples)'), findsOneWidget);
      expect(valueOf(tester, 'live-valid-share'), '85 %');
      for (final (region, count) in [
        ('eye', '10'),
        ('mouth', '5'),
        ('face_other', '15'),
        ('outside', '4'),
        ('uncertain', '6'),
      ]) {
        expect(valueOf(tester, 'live-region-$region'), count, reason: region);
      }
      final bar = tester.widget<FractionallySizedBox>(
        find.descendant(
          of: key('live-region-face_other'),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(bar.widthFactor, closeTo(15 / 40, 1e-9));
    });

    testWidgets('lists the latest events, newest first', (tester) async {
      useWindow(tester, 1440, 2600);
      await openPilot(tester, liveBed());
      await tapKey(tester, 'monitor-21');

      final events = key('live-events');
      expect(events, findsOneWidget);
      expect(find.descendant(of: events, matching: find.text('00:59.000')), findsOneWidget);
      expect(find.descendant(of: events, matching: find.text('segment_start')), findsOneWidget);
      expect(find.descendant(of: events, matching: find.text('segment=practice')), findsOneWidget);
      final resume = tester.getTopLeft(find.descendant(of: events, matching: find.text('resume')));
      final start = tester.getTopLeft(find.descendant(of: events, matching: find.text('segment_start')));
      expect(resume.dy, lessThan(start.dy));
    });

    testWidgets('a synthetic estimator gets a clear warning', (tester) async {
      useWindow(tester, 1440, 2600);
      await openPilot(tester, liveBed(queue: [liveStatus(synthetic: true)]));
      await tapKey(tester, 'monitor-21');

      expect(key('live-synthetic-warning'), findsOneWidget);
      expect(find.text('Synthetic estimator'), findsOneWidget);
      expect(find.textContaining('mean nothing'), findsOneWidget);
    });

    testWidgets('an ended session stops the polling', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = liveBed(queue: [
        liveStatus(),
        liveStatus(status: 'ended', endReason: 'completed'),
      ]);
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');
      await fire(tester, armed(bed).single);

      expect(textOf(tester, 'live-status'), 'Completed');
      expect(key('live-ended-note'), findsOneWidget);
      expect(armed(bed), isEmpty, reason: 'no more reads after the end');
      expect(bed.pilot.liveCalls, hasLength(2));
    });

    testWidgets('closing the panel cancels the polling', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = liveBed();
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');
      final timer = armed(bed).single;

      await tapKey(tester, 'live-close');
      expect(key('live-panel'), findsNothing);
      expect(timer.cancelled, isTrue);
      timer.fire();
      await tester.pumpAndSettle();
      expect(bed.pilot.liveCalls, hasLength(1), reason: 'a cancelled timer reads nothing');
    });

    testWidgets('leaving the section or the tab stops the polling; coming back resumes',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = liveBed();
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');
      final timer = armed(bed).single;

      // Another tab: polling pauses.
      await openTab(tester, 'Analysis');
      expect(timer.cancelled, isTrue);
      expect(armed(bed), isEmpty);
      expect(bed.pilot.liveCalls, hasLength(1));

      // Back: one read at once, and the timer runs again.
      await openTab(tester, 'Pilot');
      expect(bed.pilot.liveCalls.map((c) => c.first), [true, false]);
      expect(armed(bed), hasLength(1));

      // Another section of the tab: the live part goes away with its timer.
      final running = armed(bed).single;
      await section(tester, 'report');
      expect(running.cancelled, isTrue);
      expect(armed(bed), isEmpty);
    });

    testWidgets('a refused read shows the server message and stops', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = liveBed();
      bed.pilot.liveFailure = const ApiException(
        'Only researchers can monitor a session.',
        statusCode: 403,
      );
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      expect(find.text('Only researchers can monitor a session.'), findsOneWidget);
      expect(armed(bed), isEmpty);
    });

    testWidgets('a network failure keeps trying', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = liveBed();
      bed.pilot.liveFailure = const ApiException('Could not reach the server.');
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');
      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(armed(bed), hasLength(1));

      bed.pilot.liveFailure = null;
      await fire(tester, armed(bed).single);
      expect(find.text('Could not reach the server.'), findsNothing);
      expect(key('live-fact-segment'), findsOneWidget);
      expect(bed.pilot.liveCalls.map((c) => c.first), [true, true],
          reason: 'the first read did not succeed, so it is still the first');
    });

    testWidgets('analysts do not get the live monitor', (tester) async {
      useWindow(tester, 1440, 1000);
      final bed = liveBed();
      await openPilot(tester, bed, role: 'analyst');
      expect(key('live-researchers-only'), findsOneWidget);
      expect(bed.pilot.activeReads, 0);
      expect(key('active-list'), findsNothing);
    });
  });

  group('Live observations', () {
    testWidgets('the form saves with the current session time', (tester) async {
      useWindow(tester, 1440, 2800);
      final bed = liveBed(observations: {
        '21': [observation('1', text: 'Looked away twice')],
      });
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      expect(find.text('Observations (1)'), findsOneWidget);
      expect(find.text('Looked away twice'), findsOneWidget);
      expect(find.text('Do not write names or identifying details.'), findsOneWidget);
      expect(
        tester.widget<TextField>(key('obs-text')).maxLength,
        2000,
      );

      await choose(tester, 'obs-category', 'Technical');
      await choose(tester, 'obs-severity', 'Major');
      await typeInto(tester, 'obs-text', '  Camera lost the face  ');
      await tapKey(tester, 'obs-use-time');
      await tapKey(tester, 'obs-save');

      final sent = bed.pilot.addedObservations.single;
      expect(sent.sessionId, '21');
      expect(sent.request.category, 'technical');
      expect(sent.request.severity, 'major');
      expect(sent.request.text, 'Camera lost the face');
      expect(sent.request.tMs, 61250, reason: 'last_sample_t_ms of the live status');
      expect(tester.widget<TextField>(key('obs-text')).controller!.text, isEmpty);
      expect(find.text('Camera lost the face'), findsOneWidget);
      expect(find.text('Observations (2)'), findsOneWidget);
      expect(find.text('at 01:01.250'), findsOneWidget);
    });

    testWidgets('without the checkbox a note is about the whole session', (tester) async {
      useWindow(tester, 1440, 2800);
      final bed = liveBed();
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      await typeInto(tester, 'obs-text', 'Needed a break');
      await tapKey(tester, 'obs-save');

      final request = bed.pilot.addedObservations.single.request;
      expect(request.tMs, isNull);
      expect(request.category, 'comfort');
      expect(request.severity, 'info');
      expect(find.text('Whole session'), findsOneWidget);
    });

    testWidgets('the session time needs a sample', (tester) async {
      useWindow(tester, 1440, 2800);
      final bed = liveBed(queue: [liveStatus(lastSampleTMs: null)]);
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      expect(find.text('No samples yet, so there is no session time.'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(key('obs-use-time')).onChanged, isNull);
    });

    testWidgets('an empty note is not sent, a refusal is shown as written',
        (tester) async {
      useWindow(tester, 1440, 2800);
      final bed = liveBed();
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      await tapKey(tester, 'obs-save');
      expect(find.text('Write what you saw before saving.'), findsOneWidget);
      expect(bed.pilot.addedObservations, isEmpty);

      bed.pilot.addObservationFailure = const ApiException(
        'observation text is limited to 2000 characters',
        statusCode: 422,
      );
      await typeInto(tester, 'obs-text', 'Something');
      await tapKey(tester, 'obs-save');
      expect(find.text('observation text is limited to 2000 characters'), findsOneWidget);
      expect(tester.widget<TextField>(key('obs-text')).controller!.text, 'Something',
          reason: 'what was typed is kept');
    });

    testWidgets('a new session starts a new list', (tester) async {
      useWindow(tester, 1440, 2800);
      final bed = liveBed(observations: {
        '21': [observation('1', text: 'About the first')],
        '22': [observation('2', session: '22', text: 'About the second')],
      });
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');
      expect(find.text('About the first'), findsOneWidget);

      await tapKey(tester, 'monitor-22');
      expect(find.text('About the first'), findsNothing);
      expect(find.text('About the second'), findsOneWidget);
    });
  });

  group('Thresholds', () {
    Future<TestBed> openThresholds(
      WidgetTester tester, {
      String role = 'researcher',
      bool history = false,
    }) async {
      useWindow(tester, 1440, 3200);
      final bed = TestBed();
      bed.pilot.reviewResult = sampleReview();
      if (history) {
        bed.measurementSettings
          ..settings = const MeasurementSettings(
            validationMinCorrect: 0.7,
            gazeConfThreshold: 0.6,
            version: 2,
          )
          ..history = settingsHistory;
      }
      await openPilot(tester, bed, role: role);
      await section(tester, 'thresholds');
      return bed;
    }

    testWidgets('shows the current settings with their version and prefilled candidates',
        (tester) async {
      await openThresholds(tester);

      expect(textOf(tester, 'threshold-version'), 'Version 1');
      expect(valueOf(tester, 'current-validation_min_correct'), '0.8');
      expect(valueOf(tester, 'current-min_region_to_error_ratio'), '2');
      expect(valueOf(tester, 'current-calibration_points'), '9');
      expect(valueOf(tester, 'current-quality_max_missing_share'), '0.2');
      expect(fieldText(tester, 'candidate-validation_min_correct'), '0.8');
      expect(fieldText(tester, 'candidate-validation_max_uncertain'), '0.2');
      expect(fieldText(tester, 'candidate-min_region_to_error_ratio'), '2');
      expect(fieldText(tester, 'candidate-gaze_conf_threshold'), '0.5');
      expect(fieldText(tester, 'candidate-quality_max_uncertain_share'), '0.2');
      expect(fieldText(tester, 'candidate-quality_max_missing_share'), '0.2');
      expect(tester.widget<SwitchListTile>(key('threshold-include-synthetic')).value, isFalse);
      expect(key('threshold-results'), findsNothing);
    });

    testWidgets('Review sends only the changed fields and shows the result',
        (tester) async {
      final bed = await openThresholds(tester);
      await typeInto(tester, 'candidate-validation_min_correct', '0.7');
      await typeInto(tester, 'candidate-gaze_conf_threshold', '0,5');
      await tapKey(tester, 'threshold-review');

      final review = bed.pilot.reviews.single;
      expect(review.changes, {'validation_min_correct': 0.7},
          reason: 'an unchanged value is not sent');
      expect(review.includeSynthetic, isFalse);

      expect(key('threshold-results'), findsOneWidget);
      expect(valueOf(tester, 'review-validation'), '1 -> 2');
      expect(valueOf(tester, 'review-quality-ok'), '1 -> 2');
      expect(valueOf(tester, 'review-quality-review'), '1 -> 0');
      expect(valueOf(tester, 'review-quality-exclude'), '1 -> 1');
      expect(valueOf(tester, 'review-changed'), '1');
      expect(find.textContaining('of 2 validated'), findsOneWidget);
      expect(find.textContaining('2 synthetic left out'), findsOneWidget);
      expect(
        find.descendant(of: key('review-notes'), matching: find.textContaining('new sessions only')),
        findsOneWidget,
      );
    });

    testWidgets('distributions, devices and rows, with changed rows highlighted',
        (tester) async {
      final bed = await openThresholds(tester);
      await tapKey(tester, 'threshold-review');
      expect(bed.pilot.reviews.single.changes, isEmpty,
          reason: 'reviewing the current values is allowed');

      // The distribution table: a metric per row with n, min ... max.
      final dist = key('review-distributions');
      for (final header in ['n', 'Min', 'p25', 'Median', 'p75', 'p90', 'Max']) {
        expect(find.descendant(of: dist, matching: find.text(header)), findsOneWidget);
      }
      for (final k in ThresholdReview.distributionKeys) {
        expect(hasRow(tester, 'review-distributions', 'dist-$k'), isTrue, reason: k);
      }
      expect(
        rowStrings(dataRow(tester, 'review-distributions', 'dist-correct_ratio')),
        ['Validation: correct share', '5', '0.5', '0.6', '0.7', '0.8', '0.9', '1'],
      );
      expect(
        rowStrings(dataRow(tester, 'review-distributions', 'dist-uncertain_ratio')),
        ['Validation: uncertain share', '0', '-', '-', '-', '-', '-', '-'],
        reason: 'no data: min ... max are dashes',
      );

      // By device.
      expect(
        rowStrings(dataRow(tester, 'review-devices', 'device-windows')),
        ['windows', '2', '2', '1', '2'],
      );
      expect(hasRow(tester, 'review-devices', 'device-android'), isTrue);

      // Rows: only the changed one is highlighted.
      DataRow row(String id) => dataRow(tester, 'review-rows', 'review-row-$id');
      expect(row('11').color!.resolve(<WidgetState>{}), AppColors.warningTint);
      expect(row('12').color, isNull);
      expect(row('13').color, isNull);
      expect(rowStrings(row('11')), contains('Changed'));
      expect(rowStrings(row('11')), containsAll(['P-001', '0.75', '0.1', '2.4', '22.5']));
      expect(rowStrings(row('12')), contains('Same'));
      expect(rowStrings(row('13')), containsAll(['P-003', 'android', '-']));
    });

    testWidgets('an invalid candidate is not sent', (tester) async {
      final bed = await openThresholds(tester);
      await typeInto(tester, 'candidate-validation_min_correct', '1.5');
      await typeInto(tester, 'candidate-min_region_to_error_ratio', '0.5');
      await typeInto(tester, 'candidate-gaze_conf_threshold', 'high');
      await tapKey(tester, 'threshold-review');

      expect(bed.pilot.reviews, isEmpty);
      expect(find.text('Enter a value from 0 to 1.'), findsOneWidget);
      expect(find.text('Enter a value of 1 or more.'), findsOneWidget);
      expect(find.text('Enter a number.'), findsOneWidget);
      expect(find.textContaining('Some values are not valid'), findsOneWidget);
    });

    testWidgets('a server refusal is shown as written', (tester) async {
      final bed = await openThresholds(tester);
      bed.pilot.reviewFailure = const ApiException(
        'validation_min_correct must be between 0 and 1',
        statusCode: 422,
      );
      await typeInto(tester, 'candidate-validation_min_correct', '0.9');
      await tapKey(tester, 'threshold-review');
      expect(find.text('validation_min_correct must be between 0 and 1'), findsOneWidget);
      expect(key('threshold-results'), findsNothing);
    });

    testWidgets('Include synthetic sessions is sent, and clears an old result',
        (tester) async {
      final bed = await openThresholds(tester);
      await tapKey(tester, 'threshold-review');
      expect(key('threshold-results'), findsOneWidget);

      await tapKey(tester, 'threshold-include-synthetic');
      expect(key('threshold-results'), findsNothing,
          reason: 'the sessions in the result depend on the switch');

      bed.pilot.reviewResult = sampleReview(includeSynthetic: true);
      await tapKey(tester, 'threshold-review');
      expect(bed.pilot.reviews.last.includeSynthetic, isTrue);
      expect(find.textContaining('synthetic ones included'), findsOneWidget);
    });

    testWidgets('Save is off until the reviewed values differ from the current ones',
        (tester) async {
      final bed = await openThresholds(tester);
      bool enabled() =>
          tester.widget<OutlinedButton>(key('threshold-save')).onPressed != null;

      expect(enabled(), isFalse, reason: 'nothing reviewed yet');
      expect(find.text('Review the values first.'), findsOneWidget);

      await tapKey(tester, 'threshold-review');
      expect(enabled(), isFalse, reason: 'no value differs');
      expect(find.text('No value differs from the current settings.'), findsOneWidget);

      await typeInto(tester, 'candidate-validation_min_correct', '0.7');
      await tapKey(tester, 'threshold-review');
      expect(enabled(), isTrue);
      expect(find.text('Saves 1 changed value as version 2.'), findsOneWidget);

      await typeInto(tester, 'candidate-validation_min_correct', '0.6');
      expect(enabled(), isFalse, reason: 'the review is out of date');
      expect(key('threshold-stale'), findsOneWidget);
      expect(bed.measurementSettings.changeSaves, isEmpty);
    });

    testWidgets('Save as new settings version asks for a rationale of 10 characters',
        (tester) async {
      final bed = await openThresholds(tester);
      await typeInto(tester, 'candidate-validation_min_correct', '0.7');
      await typeInto(tester, 'candidate-quality_max_missing_share', '0.3');
      await tapKey(tester, 'threshold-review');
      await tapKey(tester, 'threshold-save');

      expect(key('save-version-dialog'), findsOneWidget);
      expect(find.text('Save as settings version 2'), findsOneWidget);
      expect(textOf(tester, 'save-change-validation_min_correct'),
          'Minimum correct share: 0.8 -> 0.7');
      expect(textOf(tester, 'save-change-quality_max_missing_share'),
          'Quality: maximum missing share: 0.2 -> 0.3');
      bool confirmEnabled() =>
          tester.widget<FilledButton>(key('save-version-confirm')).onPressed != null;

      expect(confirmEnabled(), isFalse, reason: 'no rationale yet');
      await tester.enterText(key('rationale-field'), 'too short');
      await tester.pump();
      expect(confirmEnabled(), isFalse, reason: '9 characters');
      await tester.enterText(key('rationale-field'), '   padded 9   ');
      await tester.pump();
      expect(confirmEnabled(), isFalse, reason: 'spaces do not count');

      await tester.enterText(key('rationale-field'), 'Too many fails on old laptops');
      await tester.pump();
      expect(confirmEnabled(), isTrue);
      await tester.tap(key('save-version-confirm'));
      await tester.pumpAndSettle();

      final saved = bed.measurementSettings.changeSaves.single;
      expect(saved.changes, {
        'validation_min_correct': 0.7,
        'quality_max_missing_share': 0.3,
      });
      expect(saved.rationale, 'Too many fails on old laptops');
      expect(key('save-version-dialog'), findsNothing);
      expect(find.text('Saved as settings version 2.'), findsOneWidget);
      expect(textOf(tester, 'threshold-version'), 'Version 2');
      expect(valueOf(tester, 'current-validation_min_correct'), '0.7');
      expect(fieldText(tester, 'candidate-validation_min_correct'), '0.7',
          reason: 'the candidates start from the new current values');
      expect(key('threshold-results'), findsNothing, reason: 'the review is done');
      // The history now has the new version with the rationale.
      expect(key('history-2'), findsOneWidget);
      expect(find.text('Too many fails on old laptops'), findsOneWidget);
    });

    testWidgets('cancelling the dialog saves nothing', (tester) async {
      final bed = await openThresholds(tester);
      await typeInto(tester, 'candidate-validation_min_correct', '0.7');
      await tapKey(tester, 'threshold-review');
      await tapKey(tester, 'threshold-save');
      await tester.tap(key('save-version-cancel'));
      await tester.pumpAndSettle();

      expect(key('save-version-dialog'), findsNothing);
      expect(bed.measurementSettings.changeSaves, isEmpty);
      expect(key('threshold-results'), findsOneWidget);
    });

    testWidgets('a refused save stays in the dialog with the server message',
        (tester) async {
      final bed = await openThresholds(tester);
      bed.measurementSettings.saveFailure = const ApiException(
        'Only researchers can change this.',
        statusCode: 403,
      );
      await typeInto(tester, 'candidate-validation_min_correct', '0.7');
      await tapKey(tester, 'threshold-review');
      await tapKey(tester, 'threshold-save');
      await tester.enterText(key('rationale-field'), 'Because of the pilot');
      await tester.pump();
      await tester.tap(key('save-version-confirm'));
      await tester.pumpAndSettle();

      expect(key('save-version-dialog'), findsOneWidget);
      expect(find.text('Only researchers can change this.'), findsOneWidget);
      expect(textOf(tester, 'threshold-version'), 'Version 1');
    });

    testWidgets('analysts can review but not save', (tester) async {
      final bed = await openThresholds(tester, role: 'analyst');
      await typeInto(tester, 'candidate-validation_min_correct', '0.7');
      await tapKey(tester, 'threshold-review');

      expect(bed.pilot.reviews, hasLength(1));
      expect(key('threshold-results'), findsOneWidget);
      expect(key('threshold-save'), findsNothing);
      expect(find.textContaining('read-only access'), findsOneWidget);
    });

    testWidgets('the settings history lists versions, date, author, rationale and changes',
        (tester) async {
      await openThresholds(tester, history: true);

      expect(textOf(tester, 'threshold-version'), 'Version 2');
      expect(key('history-2'), findsOneWidget);
      expect(key('history-1'), findsOneWidget);
      expect(
        find.descendant(of: key('history-2'), matching: find.text('2026-09-29 10:00 UTC')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('history-2'), matching: find.text('Author: user #7')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('history-2'), matching: find.text('Too many fails on old laptops')),
        findsOneWidget,
      );
      expect(textOf(tester, 'history-2-validation_min_correct'),
          'Minimum correct share: 0.8 -> 0.7');
      expect(textOf(tester, 'history-2-gaze_conf_threshold'),
          'Gaze confidence threshold: 0.5 -> 0.6');
      expect(
        find.descendant(of: key('history-1'), matching: find.text('No date (defaults)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('history-1'), matching: find.text('Author: -')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('history-1'),
          matching: find.text('No earlier version to compare with.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unreadable history shows the server message', (tester) async {
      useWindow(tester, 1440, 3200);
      final bed = TestBed();
      bed.pilot.historyFailure = const ApiException('Not a member.', statusCode: 403);
      await openPilot(tester, bed);
      await section(tester, 'thresholds');
      expect(find.text('Not a member.'), findsOneWidget);
    });
  });

  group('Tracker comparison', () {
    Future<TestBed> openTracker(
      WidgetTester tester, {
      String role = 'researcher',
      bool withRecording = true,
      bool select = true,
    }) async {
      useWindow(tester, 1440, 4200);
      final bed = TestBed();
      bed.pilot.comparisonResult = sampleComparison();
      if (withRecording) bed.pilot.recordingsBySession['21'] = [existingRecording];
      await openPilot(tester, bed, role: role);
      await section(tester, 'tracker');
      if (select) await choose(tester, 'tracker-session', 'P-001, 2026-09-29 08:00 UTC, Ended, synthetic');
      return bed;
    }

    Future<void> fillImportForm(WidgetTester tester) async {
      await typeInto(tester, 'tracker-source', 'Tobii Pro Spark');
      await typeInto(tester, 'tracker-time_column', 'time_ms');
      await typeInto(tester, 'tracker-x_column', 'gaze_x');
      await typeInto(tester, 'tracker-y_column', 'gaze_y');
    }

    testWidgets('lists the study sessions and loads the recordings of the chosen one',
        (tester) async {
      final bed = await openTracker(tester, select: false);
      expect(key('tracker-import-card'), findsNothing, reason: 'no session yet');
      expect(key('tracker-recordings'), findsNothing);

      await tapKey(tester, 'tracker-session');
      for (final label in [
        'P-001, 2026-09-29 08:00 UTC, Ended, synthetic',
        'P-002, 2026-09-30 09:30 UTC, Calibrated',
        'P-003, 2026-10-01 10:15 UTC, Ended',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('P-001, 2026-09-29 08:00 UTC, Ended, synthetic').last);
      await tester.pumpAndSettle();

      expect(key('tracker-import-card'), findsOneWidget);
      expect(key('recording-901'), findsOneWidget);
      expect(find.text('Tobii Pro Spark'), findsOneWidget);
      expect(find.text('5000 samples, 4800 valid'), findsOneWidget);
      expect(find.textContaining('Alignment estimated from the data (shift -120.0 ms)'),
          findsOneWidget);
      expect(bed.pilot.compares, isEmpty);
    });

    testWidgets('the import form explains the origin and names every option',
        (tester) async {
      await openTracker(tester);
      expect(
        find.text("Run the Participant App full screen (F11) on the tracker's screen so origin is 0, 0."),
        findsOneWidget,
      );
      for (final label in [
        'Choose file',
        'Tracker name and model',
        'Time column',
        'X column',
        'Y column',
        'Valid column (optional)',
        'Valid values (optional)',
        'Time unit',
        'Offset',
        'Coordinate space',
        'Origin x (CSS px)',
        'Origin y (CSS px)',
        'Delimiter',
        'Auto-align window (ms)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(fieldText(tester, 'tracker-offset'), '0');
      expect(fieldText(tester, 'tracker-origin_x'), '0');
      expect(fieldText(tester, 'tracker-auto_align_window_ms'), '0');
    });

    testWidgets('checks the form before anything is sent', (tester) async {
      final bed = await openTracker(tester);
      await tapKey(tester, 'tracker-import');

      expect(find.text('Choose the tracker export first.'), findsOneWidget);
      expect(find.text("Enter the tracker's name and model."), findsOneWidget);
      expect(find.text('Enter the column name.'), findsNWidgets(3));

      bed.mediaPicker.next = PickedMedia(
        name: 'empty.csv',
        bytes: Uint8List(0),
        contentType: 'text/csv',
      );
      await tapKey(tester, 'tracker-pick-file');
      await typeInto(tester, 'tracker-source', 'x' * 121);
      await typeInto(tester, 'tracker-offset', 'soon');
      await typeInto(tester, 'tracker-origin_x', '');
      await typeInto(tester, 'tracker-auto_align_window_ms', '20000');
      await tapKey(tester, 'tracker-import');

      expect(find.text('The file is empty.'), findsOneWidget);
      expect(find.text('At most 120 characters.'), findsOneWidget);
      expect(find.text('Enter a number.'), findsNWidgets(2));
      expect(find.text('Enter a whole number from 0 to 10000.'), findsOneWidget);
      expect(bed.pilot.imports, isEmpty);
    });

    testWidgets('imports the chosen file with every option and lists the recording',
        (tester) async {
      final bed = await openTracker(tester, withRecording: false);
      bed.mediaPicker.next = PickedMedia(
        name: 'tobii.tsv',
        bytes: Uint8List(2048),
        contentType: 'text/tab-separated-values',
      );
      await tapKey(tester, 'tracker-pick-file');
      expect(bed.mediaPicker.accepts.last, '.csv,.tsv,.txt');
      expect(textOf(tester, 'tracker-file-name'), 'tobii.tsv (2.0 KB)');

      await fillImportForm(tester);
      await typeInto(tester, 'tracker-valid_column', 'validity');
      await typeInto(tester, 'tracker-valid_values', '0,ok');
      await choose(tester, 'tracker-time_unit', 'Microseconds (us)');
      await typeInto(tester, 'tracker-offset', '1500,5');
      await choose(tester, 'tracker-coord_space', 'Normalised (0 to 1)');
      await typeInto(tester, 'tracker-origin_x', '-3');
      await typeInto(tester, 'tracker-origin_y', '4.25');
      await choose(tester, 'tracker-delimiter', 'Tab');
      await typeInto(tester, 'tracker-auto_align_window_ms', '2000');
      await tapKey(tester, 'tracker-import');

      final sent = bed.pilot.imports.single;
      expect(sent.sessionId, '21');
      expect(sent.filename, 'tobii.tsv');
      expect(sent.size, 2048);
      expect(sent.request.toFields(), {
        'source': 'Tobii Pro Spark',
        'time_column': 'time_ms',
        'x_column': 'gaze_x',
        'y_column': 'gaze_y',
        'valid_column': 'validity',
        'valid_values': '0,ok',
        'time_unit': 'us',
        'offset': '1500.5',
        'coord_space': 'norm',
        'origin_x': '-3',
        'origin_y': '4.25',
        'delimiter': '\t',
        'auto_align_window_ms': '2000',
      });
      expect(find.text('Imported 1200 samples (1100 valid) from Tobii Pro Spark.'),
          findsOneWidget);
      expect(key('recording-901'), findsOneWidget);
      expect(key('tracker-file-name'), findsNothing, reason: 'the file is cleared');
    });

    testWidgets('the server 422 text is shown as written', (tester) async {
      final bed = await openTracker(tester, withRecording: false);
      bed.pilot.importFailure = const ApiException(
        "time column 'time_ms' not found; the file has columns: timestamp, x, y, valid",
        statusCode: 422,
      );
      await tapKey(tester, 'tracker-pick-file');
      await fillImportForm(tester);
      await tapKey(tester, 'tracker-import');

      expect(
        find.text("time column 'time_ms' not found; the file has columns: timestamp, x, y, valid"),
        findsOneWidget,
      );
      expect(bed.pilot.imports, isEmpty);
      expect(key('tracker-import-notice'), findsNothing);
    });

    testWidgets('Compare uses a tolerance of 40 ms and shows the agreement',
        (tester) async {
      final bed = await openTracker(tester);
      expect(fieldText(tester, 'tracker-tolerance'), '40');
      await tapKey(tester, 'compare-901');

      expect(bed.pilot.compares.single, (
        sessionId: '21',
        recordingId: '901',
        toleranceMs: 40,
      ));
      expect(key('comparison-card'), findsOneWidget);
      expect(valueOf(tester, 'cmp-agreement'), '82 %');
      expect(find.text('of 400 paired samples'), findsOneWidget);
      expect(find.text('0.61'), findsOneWidget);
      expect(find.text('87 %'), findsOneWidget);
      expect(find.text('86 %'), findsOneWidget);
      expect(textOf(tester, 'cmp-bias'),
          'Bias (webcam minus tracker): x +3.2 px, y -1.4 px.');
      // Distances: n and the percentiles.
      final distance = key('cmp-distance');
      expect(find.descendant(of: distance, matching: find.text('400')), findsOneWidget);
      expect(find.descendant(of: distance, matching: find.text('10.2')), findsOneWidget);
      // Counts.
      expect(find.text('500'), findsOneWidget);
      expect(find.text('while the tracker was valid'), findsOneWidget);
    });

    testWidgets('the confusion matrix has webcam rows and tracker columns', (tester) async {
      await openTracker(tester);
      await tapKey(tester, 'compare-901');

      String cell(String web, String ref) => tester
          .widget<Text>(find.descendant(of: key('cm-$web-$ref'), matching: find.byType(Text)))
          .data!;
      expect(find.text('Webcam \\ Tracker'), findsOneWidget);
      expect(cell('eye', 'eye'), '100');
      expect(cell('eye', 'mouth'), '5');
      expect(cell('mouth', 'eye'), '4');
      expect(cell('face_other', 'eye'), '12');
      expect(cell('face_other', 'outside'), '3');
      expect(cell('outside', 'face_other'), '2');
      expect(cell('outside', 'outside'), '40');
      expect(
        find.text('Rows are what the webcam said, columns what the tracker said.'),
        findsOneWidget,
      );
      // Per-segment eye shares; a missing share is a dash, not 0 %.
      expect(rowStrings(dataRow(tester, 'cmp-segments', 'cmp-segment-baseline')),
          ['baseline', '100', '30 %', '35 %']);
      expect(rowStrings(dataRow(tester, 'cmp-segments', 'cmp-segment-post')),
          ['post', '90', '—', '—']);
    });

    testWidgets('the caveats are in a prominent warning box', (tester) async {
      await openTracker(tester);
      await tapKey(tester, 'compare-901');

      final box = key('comparison-caveats');
      expect(box, findsOneWidget);
      expect(find.descendant(of: box, matching: find.text('Read these numbers with care')),
          findsOneWidget);
      for (final caveat in comparisonCaveats) {
        expect(find.descendant(of: box, matching: find.text(caveat)), findsOneWidget);
      }
      // Above the numbers.
      expect(
        tester.getTopLeft(box).dy,
        lessThan(tester.getTopLeft(key('cmp-agreement')).dy),
      );
    });

    testWidgets('no caveats, no warning box', (tester) async {
      final bed = await openTracker(tester);
      bed.pilot.comparisonResult = sampleComparison(caveats: false);
      await tapKey(tester, 'compare-901');
      expect(key('comparison-card'), findsOneWidget);
      expect(key('comparison-caveats'), findsNothing);
    });

    testWidgets('a tolerance is checked and sent', (tester) async {
      final bed = await openTracker(tester);
      await typeInto(tester, 'tracker-tolerance', '0');
      await tapKey(tester, 'compare-901');
      expect(find.text('Enter a whole number of ms from 1 to 500.'), findsOneWidget);
      expect(bed.pilot.compares, isEmpty);

      await typeInto(tester, 'tracker-tolerance', '501');
      await tapKey(tester, 'compare-901');
      expect(bed.pilot.compares, isEmpty);

      await typeInto(tester, 'tracker-tolerance', '120');
      await tapKey(tester, 'compare-901');
      expect(bed.pilot.compares.single.toleranceMs, 120);
    });

    testWidgets('a failed comparison shows the server message', (tester) async {
      final bed = await openTracker(tester);
      bed.pilot.compareFailure = const ApiException(
        'reference recording not found',
        statusCode: 404,
      );
      await tapKey(tester, 'compare-901');
      expect(find.text('reference recording not found'), findsOneWidget);
      expect(key('comparison-card'), findsNothing);
    });

    testWidgets('analysts can compare but cannot import', (tester) async {
      final bed = await openTracker(tester, role: 'analyst');
      expect(key('tracker-import-card'), findsNothing);
      expect(key('tracker-import'), findsNothing);
      expect(key('tracker-pick-file'), findsNothing);
      await tapKey(tester, 'compare-901');
      expect(bed.pilot.compares, hasLength(1));
      expect(key('comparison-card'), findsOneWidget);
    });

    testWidgets('no recording yet says so', (tester) async {
      await openTracker(tester, withRecording: false);
      expect(find.text('No tracker export has been imported for this session.'),
          findsOneWidget);
    });

    testWidgets('a session list that cannot be read shows the server message',
        (tester) async {
      useWindow(tester, 1440, 2000);
      final bed = TestBed(sessions: FakeSessionsRepository()..failure = const ApiException('Not a member.', statusCode: 403));
      await openPilot(tester, bed, role: 'admin');
      await section(tester, 'tracker');
      expect(find.text('Not a member.'), findsOneWidget);
    });
  });

  group('Report', () {
    Future<TestBed> openReport(
      WidgetTester tester, {
      String role = 'researcher',
      double width = 1440,
    }) async {
      useWindow(tester, width, width < 500 ? 2400 : 5200);
      final bed = TestBed();
      bed.pilot.reportResult = sampleReport();
      await openPilot(tester, bed, role: role);
      await section(tester, 'report');
      return bed;
    }

    testWidgets('shows the summary tiles', (tester) async {
      final bed = await openReport(tester);
      expect(bed.pilot.reportRequests, [false]);
      expect(valueOf(tester, 'tile-sessions'), '2');
      expect(valueOf(tester, 'tile-participants'), '2');
      expect(valueOf(tester, 'tile-validation'), '1 of 2');
      expect(find.text('sessions with a validation'), findsOneWidget);
      expect(valueOf(tester, 'tile-quality-ok'), '1');
      expect(valueOf(tester, 'tile-quality-review'), '1');
      expect(valueOf(tester, 'tile-quality-exclude'), '0');
      expect(valueOf(tester, 'tile-ended-early'), '1');
      expect(find.textContaining('1 synthetic session left out'), findsOneWidget);
      expect(find.textContaining('Settings version 3'), findsOneWidget);
    });

    testWidgets('by device, comfort values and the debrief statistics', (tester) async {
      await openReport(tester);
      expect(
        rowStrings(dataRow(tester, 'report-devices', 'report-device-windows')),
        ['windows', '2', '2', '1', '1'],
      );

      expect(valueOf(tester, 'comfort-3'), '2');
      expect(valueOf(tester, 'comfort-5'), '1');
      expect(valueOf(tester, 'comfort-1'), '0');

      expect(find.text('1 answered, 1 skipped.'), findsOneWidget);
      DataRow stat(String k) => dataRow(tester, 'report-debrief', 'debrief-stat-$k');
      expect(rowStrings(stat('comfort_overall')), [
        'How comfortable did you feel?',
        'comfort_overall, Scale',
        '1',
        '4: 1',
        '4',
      ]);
      expect(rowStrings(stat('anything_uncomfortable')).sublist(2),
          ['1', 'Yes: 1', '-']);
      expect(rowStrings(stat('one_change')).sublist(2), ['1', 'see comments', '-']);
    });

    testWidgets('comments and observations list the code, category, severity, text and time',
        (tester) async {
      await openReport(tester);
      final comments = key('report-comments');
      expect(find.descendant(of: comments, matching: find.text('P-001')), findsOneWidget);
      expect(find.descendant(of: comments, matching: find.text('A brighter room please')),
          findsOneWidget);

      final obs = key('report-observations');
      expect(find.descendant(of: obs, matching: find.text('P-001')), findsNWidgets(2));
      expect(find.descendant(of: obs, matching: find.text('Looked away twice')), findsOneWidget);
      expect(find.descendant(of: obs, matching: find.text('Camera lost the face twice')),
          findsOneWidget);
      expect(find.descendant(of: obs, matching: find.text('Comfort')), findsOneWidget);
      expect(find.descendant(of: obs, matching: find.text('Technical')), findsOneWidget);
      expect(find.descendant(of: obs, matching: find.text('Major')), findsOneWidget);
      expect(find.descendant(of: obs, matching: find.text('Info')), findsOneWidget);
      expect(find.descendant(of: obs, matching: find.text('at 00:04.200')), findsOneWidget);
      expect(find.descendant(of: obs, matching: find.text('Whole session')), findsOneWidget);
      expect(key('report-observation-matrix'), findsOneWidget);
    });

    testWidgets('the session table has a row per session', (tester) async {
      await openReport(tester);
      final first = rowStrings(dataRow(tester, 'report-rows', 'report-row-21'));
      expect(first, containsAll(['P-001', 'Completed', '0:advance;1:hold', 'answered', '2 (1 major or stop)']));
      final second = rowStrings(dataRow(tester, 'report-rows', 'report-row-22'));
      expect(second, containsAll(['P-002', 'Ended early', 'skipped']));
      expect(tester.widget<DataTable>(key('report-rows')).rows, hasLength(2));
      // The table scrolls sideways.
      final scroll = tester.widget<SingleChildScrollView>(
        find
            .ancestor(of: key('report-rows'), matching: find.byType(SingleChildScrollView))
            .first,
      );
      expect(scroll.scrollDirection, Axis.horizontal);
    });

    testWidgets('Include synthetic sessions reads the report again', (tester) async {
      final bed = await openReport(tester);
      bed.pilot.reportResult = sampleReport(includeSynthetic: true);
      await tapKey(tester, 'report-include-synthetic');
      expect(bed.pilot.reportRequests, [false, true]);
      expect(find.textContaining('synthetic sessions included'), findsOneWidget);
    });

    testWidgets('Download CSV hands the file to the browser', (tester) async {
      final bed = await openReport(tester);
      await tapKey(tester, 'report-download');

      expect(bed.pilot.csvRequests, [false]);
      final file = bed.saver.saved.single;
      expect(file.name, 'pilot_sessions_study1.csv');
      expect(file.type, 'text/csv;charset=utf-8');
      expect(file.bytes, bed.pilot.csvBytes);
      expect(find.text('Downloaded pilot_sessions_study1.csv (5 B).'), findsOneWidget);
    });

    testWidgets('the CSV follows the synthetic switch', (tester) async {
      final bed = await openReport(tester);
      await tapKey(tester, 'report-include-synthetic');
      await tapKey(tester, 'report-download');
      expect(bed.pilot.csvRequests, [true]);
    });

    testWidgets('a failed download shows the server message', (tester) async {
      final bed = await openReport(tester);
      bed.pilot.csvFailure = const ApiException('Not allowed.', statusCode: 403);
      await tapKey(tester, 'report-download');
      expect(find.text('Not allowed.'), findsOneWidget);
      expect(bed.saver.saved, isEmpty);
    });

    testWidgets('analysts read the report and download it', (tester) async {
      final bed = await openReport(tester, role: 'analyst');
      expect(key('report-rows'), findsOneWidget);
      await tapKey(tester, 'report-download');
      expect(bed.saver.saved, hasLength(1));
    });

    testWidgets('a refused report shows the server message and a retry', (tester) async {
      useWindow(tester, 1440, 2000);
      final bed = TestBed();
      bed.pilot.reportFailure = const ApiException('Not a member.', statusCode: 403);
      await openPilot(tester, bed, role: 'admin');
      await section(tester, 'report');
      expect(find.text('Not a member.'), findsOneWidget);
      expect(key('report-retry'), findsOneWidget);

      bed.pilot.reportFailure = null;
      bed.pilot.reportResult = sampleReport();
      await tapKey(tester, 'report-retry');
      expect(key('report-rows'), findsOneWidget);
    });
  });

  group('Questions after a session', () {
    Future<TestBed> openDebrief(
      WidgetTester tester, {
      String role = 'researcher',
      DebriefForm? form,
    }) async {
      useWindow(tester, 1440, 4200);
      final bed = TestBed();
      bed.pilot.form = form ?? sampleForm();
      await openPilot(tester, bed, role: role);
      await section(tester, 'debrief');
      return bed;
    }

    testWidgets('shows the version, the switch and the questions', (tester) async {
      await openDebrief(tester);
      expect(textOf(tester, 'debrief-version'), 'Version 2');
      expect(tester.widget<SwitchListTile>(key('debrief-enabled')).value, isTrue);
      expect(fieldText(tester, 'q-key-0'), 'comfort_overall');
      expect(fieldText(tester, 'q-prompt-0'), 'How comfortable did you feel?');
      expect(fieldText(tester, 'q-scale-max-0'), '5');
      expect(fieldText(tester, 'q-labels-0'),
          'Very uncomfortable\nUncomfortable\nNeutral\nComfortable\nVery comfortable');
      expect(tester.widget<Checkbox>(key('q-required-0')).value, isTrue);
      expect(fieldText(tester, 'q-options-2'), 'Lab\nOffice');
      expect(key('q-scale-max-1'), findsNothing, reason: 'only scale questions have it');
      expect(key('q-options-0'), findsNothing);
      expect(
        find.textContaining('Changing the questions creates a new version'),
        findsOneWidget,
      );
      expect(find.textContaining('answers already given keep the version'), findsOneWidget);
    });

    testWidgets('an unsaved form offers the suggested questions as version 1',
        (tester) async {
      final bed = await openDebrief(
        tester,
        form: sampleForm(version: 0, enabled: false, saved: false),
      );
      expect(textOf(tester, 'debrief-version'), 'Not saved yet');
      expect(find.textContaining('saving stores them as version 1'), findsOneWidget);

      await tapKey(tester, 'debrief-enabled');
      await tapKey(tester, 'debrief-save');

      final save = bed.pilot.debriefSaves.single;
      expect(save.enabled, isTrue);
      expect(save.questions, hasLength(4));
      expect(textOf(tester, 'debrief-version'), 'Version 1');
      expect(find.textContaining('Saved as version 1'), findsOneWidget);
    });

    testWidgets('the switch alone does not make a new version', (tester) async {
      final bed = await openDebrief(tester);
      expect(tester.widget<FilledButton>(key('debrief-save')).onPressed, isNull,
          reason: 'nothing to save yet');

      await tapKey(tester, 'debrief-enabled');
      await tapKey(tester, 'debrief-save');

      final save = bed.pilot.debriefSaves.single;
      expect(save.enabled, isFalse);
      expect(save.questions, isNull, reason: 'the questions did not change');
      expect(textOf(tester, 'debrief-version'), 'Version 2');
      expect(find.text('Participants are no longer asked these questions.'), findsOneWidget);
    });

    testWidgets('a changed question makes the next version and old answers keep theirs',
        (tester) async {
      final bed = await openDebrief(tester);
      expect(key('debrief-will-version'), findsNothing);
      await typeInto(tester, 'q-prompt-1', 'Was anything upsetting?');
      expect(textOf(tester, 'debrief-will-version'), 'Saving will create version 3.');
      await tapKey(tester, 'debrief-save');

      final save = bed.pilot.debriefSaves.single;
      expect(save.questions![1].prompt, 'Was anything upsetting?');
      expect(save.questions!.map((q) => q.key), [
        'comfort_overall',
        'anything_uncomfortable',
        'room',
        'one_change',
      ]);
      expect(textOf(tester, 'debrief-version'), 'Version 3');
      expect(
        find.text('Saved as version 3. Answers already given keep the version they were answered for.'),
        findsOneWidget,
      );
      expect(key('debrief-will-version'), findsNothing);
    });

    testWidgets('questions can be added, removed and reordered', (tester) async {
      final bed = await openDebrief(tester);
      await tapKey(tester, 'q-down-0');
      await tapKey(tester, 'q-remove-3');
      await tapKey(tester, 'debrief-add');

      expect(fieldText(tester, 'q-key-0'), 'anything_uncomfortable');
      expect(fieldText(tester, 'q-key-1'), 'comfort_overall');
      expect(fieldText(tester, 'q-key-3'), 'question_4');
      expect(key('q-key-4'), findsNothing);
      await typeInto(tester, 'q-prompt-3', 'Anything else?');
      await tapKey(tester, 'debrief-save');

      final keys = bed.pilot.debriefSaves.single.questions!.map((q) => q.key).toList();
      expect(keys, ['anything_uncomfortable', 'comfort_overall', 'room', 'question_4']);
      expect(bed.pilot.debriefSaves.single.questions![0].prompt, 'Was anything uncomfortable?');
      // The first and the last question cannot move past the ends.
      expect(tester.widget<IconButton>(key('q-up-0')).onPressed, isNull);
      expect(tester.widget<IconButton>(key('q-down-3')).onPressed, isNull);
    });

    testWidgets('changing the type shows the fields of that type', (tester) async {
      final bed = await openDebrief(tester);
      await choose(tester, 'q-type-3', 'Scale');
      expect(key('q-scale-max-3'), findsOneWidget);
      expect(key('q-labels-3'), findsOneWidget);

      await choose(tester, 'q-type-3', 'Choice');
      expect(key('q-scale-max-3'), findsNothing);
      await typeInto(tester, 'q-options-3', 'Yes\nNo\nMaybe');
      await tapKey(tester, 'debrief-save');

      final q = bed.pilot.debriefSaves.single.questions![3];
      expect(q.type, 'choice');
      expect(q.options, ['Yes', 'No', 'Maybe']);
      expect(q.toJson().containsKey('scale_max'), isFalse);
    });

    testWidgets('checks keys, prompts, scales and options before saving',
        (tester) async {
      final bed = await openDebrief(tester);
      await typeInto(tester, 'q-key-1', 'comfort_overall');
      await typeInto(tester, 'q-prompt-3', '');
      await typeInto(tester, 'q-labels-0', 'low\nhigh');
      await typeInto(tester, 'q-options-2', 'Only one');
      await tapKey(tester, 'debrief-save');

      expect(bed.pilot.debriefSaves, isEmpty);
      expect(textOf(tester, 'q-problem-1'), 'The key "comfort_overall" is used twice.');
      expect(textOf(tester, 'q-problem-3'), startsWith('The prompt is required'));
      expect(textOf(tester, 'q-problem-0'), 'Give one label per point (5) or none.');
      expect(textOf(tester, 'q-problem-2'), startsWith('A choice needs 2 to 10 options'));
      expect(find.textContaining('Some questions are not valid'), findsOneWidget);

      await typeInto(tester, 'q-key-1', '1bad');
      await tapKey(tester, 'debrief-save');
      expect(textOf(tester, 'q-problem-1'), startsWith('The key starts with a letter'));

      // The scale needs 2 to 10 points.
      await typeInto(tester, 'q-scale-max-0', '11');
      await tapKey(tester, 'debrief-save');
      expect(textOf(tester, 'q-problem-0'), 'The scale goes from 2 to 10 points.');
    });

    testWidgets('a form holds at most 20 questions', (tester) async {
      final bed = await openDebrief(tester);
      for (var i = 0; i < 16; i++) {
        await tapKey(tester, 'debrief-add');
      }
      expect(tester.widget<OutlinedButton>(key('debrief-add')).onPressed, isNull);
      expect(find.text('A form holds at most 20 questions.'), findsOneWidget);
      expect(bed.pilot.debriefSaves, isEmpty);
    });

    testWidgets('Discard puts the saved questions back', (tester) async {
      await openDebrief(tester);
      await typeInto(tester, 'q-prompt-0', 'Changed');
      await tapKey(tester, 'q-remove-1');
      await tapKey(tester, 'debrief-discard');
      expect(fieldText(tester, 'q-prompt-0'), 'How comfortable did you feel?');
      expect(key('q-key-3'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(key('debrief-discard')).onPressed, isNull);
    });

    testWidgets('the server 422 is shown as written and the editor keeps its work',
        (tester) async {
      final bed = await openDebrief(tester);
      bed.pilot.debriefSaveFailure = const ApiException(
        'questions[1].prompt is required (max 300 characters)',
        statusCode: 422,
      );
      await typeInto(tester, 'q-prompt-0', 'Edited');
      await tapKey(tester, 'debrief-save');
      expect(find.text('questions[1].prompt is required (max 300 characters)'), findsOneWidget);
      expect(fieldText(tester, 'q-prompt-0'), 'Edited');
    });

    testWidgets('analysts read the questions without editing them', (tester) async {
      final bed = await openDebrief(tester, role: 'analyst');
      expect(key('debrief-read-only'), findsOneWidget);
      expect(key('debrief-enabled'), findsNothing);
      expect(key('debrief-save'), findsNothing);
      expect(key('debrief-add'), findsNothing);
      expect(key('q-prompt-0'), findsNothing);
      expect(textOf(tester, 'debrief-enabled-readonly'),
          'Participants are asked these questions after a session.');
      expect(
        find.descendant(of: key('question-0'), matching: find.textContaining('1. How comfortable')),
        findsOneWidget,
      );
      expect(find.textContaining('Scale 1 to 5: Very uncomfortable'), findsOneWidget);
      expect(find.textContaining('Choice: Lab, Office'), findsOneWidget);
      expect(bed.pilot.debriefSaves, isEmpty);
    });

    testWidgets('a form that cannot be read shows the server message and a retry',
        (tester) async {
      useWindow(tester, 1440, 2000);
      final bed = TestBed();
      bed.pilot.debriefLoadFailure = const ApiException('Not a member.', statusCode: 403);
      await openPilot(tester, bed, role: 'admin');
      await section(tester, 'debrief');
      expect(find.text('Not a member.'), findsOneWidget);
      expect(key('debrief-retry'), findsOneWidget);
    });
  });

  group('Observations on the session detail', () {
    Future<TestBed> openDetail(WidgetTester tester, {String role = 'researcher'}) async {
      useWindow(tester, 1440, 900);
      final bed = TestBed();
      bed.pilot.observationsBySession['21'] = [
        observation('1', text: 'Looked away twice', tMs: 4200, severity: 'minor'),
      ];
      await openStudy(tester, bed, role: role);
      await openTab(tester, 'Sessions');
      await tester.tap(find.text('P-001'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        key('observations-panel'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      return bed;
    }

    testWidgets('lists the observations and lets a researcher add one', (tester) async {
      final bed = await openDetail(tester);
      expect(find.text('Observations (1)'), findsOneWidget);
      expect(find.text('Looked away twice'), findsOneWidget);
      expect(find.text('at 00:04.200'), findsOneWidget);
      expect(find.text('Minor'), findsOneWidget);
      expect(key('obs-use-time'), findsNothing,
          reason: 'there is no live session time on the detail');

      await typeInto(tester, 'obs-text', 'Asked to repeat the instructions');
      await tapKey(tester, 'obs-save');
      expect(bed.pilot.addedObservations.single.sessionId, '21');
      expect(bed.pilot.addedObservations.single.request.tMs, isNull);
      expect(find.text('Asked to repeat the instructions'), findsOneWidget);
      expect(find.text('Observations (2)'), findsOneWidget);
    });

    testWidgets('analysts read the observations without the form', (tester) async {
      await openDetail(tester, role: 'analyst');
      expect(find.text('Looked away twice'), findsOneWidget);
      expect(key('obs-text'), findsNothing);
      expect(key('obs-save'), findsNothing);
    });
  });

  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('every section renders without overflow at ${width.toInt()} px',
        (tester) async {
      useWindow(tester, width, width == 360 ? 740 : 900);
      final bed = liveBed(observations: {
        '21': [observation('1', tMs: 4200, severity: 'major')],
      });
      bed.pilot
        ..reviewResult = sampleReview()
        ..comparisonResult = sampleComparison()
        ..reportResult = sampleReport()
        ..form = sampleForm()
        ..recordingsBySession['21'] = [existingRecording];
      bed.measurementSettings.history = settingsHistory;
      await openPilot(tester, bed);

      // Live with a watched session and the observation form.
      await tapKey(tester, 'monitor-21');
      expect(key('live-panel'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'live-close');

      // Thresholds with a review.
      await section(tester, 'thresholds');
      await typeInto(tester, 'candidate-validation_min_correct', '0.7');
      await tapKey(tester, 'threshold-review');
      expect(key('threshold-results'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'threshold-save');
      expect(key('save-version-dialog'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(key('save-version-cancel'));
      await tester.pumpAndSettle();

      // Tracker comparison with the import form and a result.
      await section(tester, 'tracker');
      await tapKey(tester, 'tracker-session');
      await tester.tap(find.textContaining('P-001, ').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'compare-901');
      expect(key('comparison-card'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Report.
      await section(tester, 'report');
      expect(key('report-rows'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Questions after a session.
      await section(tester, 'debrief');
      expect(key('question-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard: Enter in a candidate field starts the review', (tester) async {
    useWindow(tester, 1440, 3200);
    final bed = TestBed();
    bed.pilot.reviewResult = sampleReview();
    await openPilot(tester, bed);
    await section(tester, 'thresholds');

    await tester.tap(key('candidate-validation_min_correct'));
    await tester.enterText(key('candidate-validation_min_correct'), '0.7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(bed.pilot.reviews.single.changes, {'validation_min_correct': 0.7});
  });
}

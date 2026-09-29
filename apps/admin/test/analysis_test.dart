import 'dart:ui' as ui;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/analysis/application/analysis_controller.dart';
import 'package:research_admin/features/analysis/domain/analysis_filters.dart';
import 'package:research_admin/features/analysis/presentation/analysis_tab.dart';
import 'package:research_admin/features/analysis/presentation/trend_chart.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openAnalysis(WidgetTester tester, TestBed bed,
    {String role = 'researcher'}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Analysis');
}

Future<void> show(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('apply-filters')));
}

/// The page is a list: scroll until the widget with [key] is on screen.
Future<void> reveal(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key, skipOffstage: false));
  await tester.pumpAndSettle();
}

void main() {
  group('filters', () {
    test('the defaults ask for ok and review, without synthetic sessions', () {
      const f = AnalysisFilters();
      expect(f.toQuery(), {
        'quality': 'ok,review',
        'include_synthetic': 'false',
      });
      expect(f.queryString, 'quality=ok,review&include_synthetic=false');
      expect(f.validate(), isNull);
    });

    test('every filter goes into the query in contract order', () {
      const f = AnalysisFilters(
        participant: ' P-001 ',
        path: 'gradual_face',
        protocolVersion: '2',
        device: 'web',
        from: '2026-09-01',
        to: '2026-09-30',
        qualities: {QualityGrade.review},
        includeSynthetic: true,
      );
      expect(f.toQuery().keys.toList(), [
        'participant',
        'path',
        'protocol_version',
        'device',
        'from',
        'to',
        'quality',
        'include_synthetic',
      ]);
      // Synthetic sessions are graded exclude: asking for them asks for it.
      expect(f.queryString,
          'participant=P-001&path=gradual_face&protocol_version=2&device=web'
          '&from=2026-09-01&to=2026-09-30&quality=review,exclude&include_synthetic=true');
    });

    test('including synthetic sessions also asks for the exclude grade', () {
      const f = AnalysisFilters(includeSynthetic: true);
      expect(f.requestedQualities, ['ok', 'review', 'exclude']);
      expect(f.toQuery()['quality'], 'ok,review,exclude');
      expect(const AnalysisFilters().requestedQualities, ['ok', 'review']);
    });

    test('quality grades keep a fixed order whatever was clicked first', () {
      const f = AnalysisFilters(qualities: {QualityGrade.review, QualityGrade.ok});
      expect(f.toQuery()['quality'], 'ok,review');
      // A grade that cannot be selected is never sent.
      const g = AnalysisFilters(qualities: {QualityGrade.exclude, QualityGrade.ok});
      expect(g.toQuery()['quality'], 'ok');
    });

    test('values are percent-encoded', () {
      const f = AnalysisFilters(participant: 'P 001&x=1');
      expect(f.queryString, contains('participant=P+001%26x%3D1'));
    });

    test('bad input is refused with a reason', () {
      expect(const AnalysisFilters(protocolVersion: 'two').validate(),
          contains('whole number'));
      expect(const AnalysisFilters(from: 'yesterday').validate(), contains('"from"'));
      expect(const AnalysisFilters(to: '31/12/2026').validate(), contains('"to"'));
      expect(
        const AnalysisFilters(from: '2026-10-01', to: '2026-09-01').validate(),
        contains('after'),
      );
      expect(const AnalysisFilters(qualities: {}).validate(), contains('quality'));
    });

    test('copyWith can clear the path', () {
      const f = AnalysisFilters(path: 'gradual_face');
      expect(f.copyWith(path: null).path, isNull);
      expect(f.copyWith(device: 'web').path, 'gradual_face');
    });
  });

  group('controller', () {
    AnalysisController make(FakeAnalysisRepository a, FakeExportsRepository e,
            RecordingFileSaver saver) =>
        AnalysisController(a, e, 1, saver.call);

    test('apply sends the filters and keeps the result', () async {
      final a = FakeAnalysisRepository();
      final c = make(a, FakeExportsRepository(), RecordingFileSaver());
      addTearDown(c.dispose);
      c
        ..setParticipant('P-001')
        ..setPath('interest_conversation')
        ..setIncludeSynthetic(true);
      expect(await c.apply(), isTrue);
      expect(a.requests.single.participant, 'P-001');
      expect(a.requests.single.path, 'interest_conversation');
      expect(a.requests.single.includeSynthetic, isTrue);
      expect(c.response!.rows.length, 4);
      expect(c.appliedFilters, a.requests.single);
    });

    test('invalid filters are not sent', () async {
      final a = FakeAnalysisRepository();
      final c = make(a, FakeExportsRepository(), RecordingFileSaver());
      addTearDown(c.dispose);
      c.setProtocolVersion('x');
      expect(await c.apply(), isFalse);
      expect(a.requests, isEmpty);
      expect(c.error, contains('whole number'));
    });

    test('the last quality grade cannot be switched off', () {
      final c = make(FakeAnalysisRepository(), FakeExportsRepository(), RecordingFileSaver());
      addTearDown(c.dispose);
      c.toggleQuality(QualityGrade.ok, false);
      expect(c.filters.qualities, {QualityGrade.review});
      c.toggleQuality(QualityGrade.review, false);
      expect(c.filters.qualities, {QualityGrade.review}, reason: 'one must stay');
      c.toggleQuality(QualityGrade.ok, true);
      expect(c.filters.qualities, {QualityGrade.ok, QualityGrade.review});
      c.toggleQuality(QualityGrade.exclude, true);
      expect(c.filters.qualities, {QualityGrade.ok, QualityGrade.review},
          reason: 'excluded sessions are never analysed');
    });

    test('a server error is shown and the old result is kept', () async {
      final a = FakeAnalysisRepository();
      final c = make(a, FakeExportsRepository(), RecordingFileSaver());
      addTearDown(c.dispose);
      await c.apply();
      a.failure = const ApiException('Not a member of this study.', statusCode: 403);
      expect(await c.apply(), isFalse);
      expect(c.error, 'Not a member of this study.');
      expect(c.response, isNotNull);
    });

    test('exports use the edited filters and hand the bytes to the browser',
        () async {
      final e = FakeExportsRepository();
      final saver = RecordingFileSaver();
      final c = make(FakeAnalysisRepository(), e, saver);
      addTearDown(c.dispose);
      c
        ..setDevice('android')
        ..toggleQuality(QualityGrade.ok, false);
      expect(await c.downloadSessionsCsv(), isTrue);
      expect(await c.downloadSessionsJson(), isTrue);
      expect(e.filters.map((f) => f.device), ['android', 'android']);
      expect(e.filters.first.qualities, {QualityGrade.review});
      expect(e.filters.first.toQuery()['quality'], 'review');
      expect(saver.saved.map((s) => s.name), ['sessions.csv', 'sessions.json']);
      expect(saver.saved.first.type, startsWith('text/csv'));
      expect(saver.saved.last.type, 'application/json');
      expect(String.fromCharCodes(saver.saved.first.bytes), 'data:sessions.csv');
      expect(c.notice, contains('sessions.json'));
    });

    test('an export with bad filters does not download anything', () async {
      final e = FakeExportsRepository();
      final saver = RecordingFileSaver();
      final c = make(FakeAnalysisRepository(), e, saver);
      addTearDown(c.dispose);
      c.setFrom('nope');
      expect(await c.downloadSessionsCsv(), isFalse);
      expect(e.calls, isEmpty);
      expect(saver.saved, isEmpty);
      expect(c.error, contains('"from"'));
    });

    test('outside the browser the download says it is not available', () async {
      final saver = RecordingFileSaver(succeeds: false);
      final c = make(FakeAnalysisRepository(), FakeExportsRepository(), saver);
      addTearDown(c.dispose);
      expect(await c.downloadSessionsCsv(), isFalse);
      expect(c.error, contains('web app'));
    });

    test('a failed download shows the server message', () async {
      final e = FakeExportsRepository()
        ..failure = const ApiException('You do not have permission to do this.', statusCode: 403);
      final c = make(FakeAnalysisRepository(), e, RecordingFileSaver());
      addTearDown(c.dispose);
      expect(await c.downloadSessionsCsv(), isFalse);
      expect(c.error, 'You do not have permission to do this.');
    });

    test('the dictionary is fetched once', () async {
      final e = FakeExportsRepository();
      final c = make(FakeAnalysisRepository(), e, RecordingFileSaver());
      addTearDown(c.dispose);
      expect((await c.loadDictionary())!.length, 2);
      await c.loadDictionary();
      expect(e.calls.where((x) => x == 'dictionary').length, 1);
    });

    test('reset puts the defaults back', () {
      final c = make(FakeAnalysisRepository(), FakeExportsRepository(), RecordingFileSaver());
      addTearDown(c.dispose);
      c
        ..setParticipant('P-9')
        ..setIncludeSynthetic(true);
      c.resetFilters();
      expect(c.filters.participant, '');
      expect(c.filters.includeSynthetic, isFalse);
    });
  });

  group('the delta with its sign', () {
    test('is written in percentage points', () {
      expect(formatEyeShareDelta(0.12), '+12 pp');
      expect(formatEyeShareDelta(-0.055), '-6 pp');
      expect(formatEyeShareDelta(0.001), '0 pp');
      expect(formatEyeShareDelta(0), '0 pp');
      expect(formatEyeShareDelta(null), 'Not evaluable');
    });
  });

  group('trend chart geometry', () {
    const points = [
      TrendPoint(sessionId: '1', baselineEyeShare: 0.2, postEyeShare: 0.5, comfortMean: 4),
      TrendPoint(sessionId: '2', comfortMean: 3),
      TrendPoint(sessionId: '3', baselineEyeShare: 0.4, postEyeShare: 0.4),
    ];
    final g = TrendGeometry.of(const Size(400, 200), points);

    test('one pair of bars per session, in order', () {
      expect(g.slots.length, 3);
      expect(g.bars.length, 6);
      expect([for (final b in g.bars) b.pointIndex], [0, 0, 1, 1, 2, 2]);
      expect([for (final b in g.bars) b.post], [false, true, false, true, false, true]);
      // Slots follow each other left to right and stay inside the plot.
      for (var i = 1; i < g.slots.length; i++) {
        expect(g.slots[i].left, closeTo(g.slots[i - 1].right, 1e-6));
      }
      for (final b in g.bars) {
        expect(g.plot.inflate(0.001).contains(b.rect.topLeft), isTrue);
        expect(b.rect.bottom, closeTo(g.plot.bottom, 1e-6));
      }
    });

    test('bar height is the share on a 0..1 scale', () {
      final base = g.bars[0];
      final post = g.bars[1];
      expect(base.hollow, isFalse);
      expect(base.rect.height, closeTo(0.2 * g.plot.height, 1e-6));
      expect(post.rect.height, closeTo(0.5 * g.plot.height, 1e-6));
      expect(g.bars[4].rect.height, closeTo(0.4 * g.plot.height, 1e-6));
    });

    test('a session without eye shares is hollow, not zero', () {
      final a = g.bars[2];
      final b = g.bars[3];
      expect(a.hollow, isTrue);
      expect(b.hollow, isTrue);
      expect(a.share, isNull);
      expect(a.rect.height, closeTo(TrendGeometry.hollowShare * g.plot.height, 1e-6));
      expect(g.bars.where((x) => x.hollow).length, 2);
    });

    test('the comfort mean is a marker at mean / 5 of the scale', () {
      expect(g.markers.length, 2, reason: 'the third session has no comfort mean');
      expect(g.markers[0].value, 4);
      expect(g.markers[0].center.dy, closeTo(g.plot.bottom - 0.8 * g.plot.height, 1e-6));
      expect(g.markers[1].center.dy, closeTo(g.plot.bottom - 0.6 * g.plot.height, 1e-6));
      // The marker sits over the middle of its session's pair of bars.
      expect(g.markers[0].center.dx, closeTo(g.slots[0].center.dx, 1e-6));
    });

    test('an empty trend and a tiny canvas do not break', () {
      final empty = TrendGeometry.of(const Size(400, 200), const []);
      expect(empty.bars, isEmpty);
      final tiny = TrendGeometry.of(const Size(10, 10), points);
      expect(tiny.bars.length, 6);
      final recorder = ui.PictureRecorder();
      TrendChartPainter(points: points).paint(Canvas(recorder), const Size(10, 10));
      TrendChartPainter(points: const []).paint(Canvas(ui.PictureRecorder()), const Size(300, 150));
      recorder.endRecording();
    });
  });

  group('Analysis tab', () {
    testWidgets('nothing is loaded before the button is pressed', (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await openAnalysis(tester, bed);
      expect(find.byKey(const Key('analysis-hint')), findsOneWidget);
      expect(bed.analysis.requests, isEmpty);
      expect(find.byKey(const Key('analysis-table')), findsNothing);
    });

    testWidgets('has every filter, quality chips and the synthetic switch (off)',
        (tester) async {
      useWindow(tester, 1440);
      await openAnalysis(tester, TestBed());
      for (final key in [
        'filter-participant',
        'filter-path',
        'filter-version',
        'filter-device',
        'filter-from',
        'filter-to',
        'filter-quality-ok',
        'filter-quality-review',
        'filter-synthetic',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      final synthetic = tester.widget<SwitchListTile>(find.byKey(const Key('filter-synthetic')));
      expect(synthetic.value, isFalse);
      expect(tester.widget<FilterChip>(find.byKey(const Key('filter-quality-ok'))).selected, isTrue);
      expect(tester.widget<FilterChip>(find.byKey(const Key('filter-quality-review'))).selected, isTrue);
    });

    testWidgets('typing filters and pressing Show analysis sends them',
        (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await openAnalysis(tester, bed);
      await tester.enterText(find.byKey(const Key('filter-participant')), 'P-001');
      await tester.enterText(find.byKey(const Key('filter-version')), '2');
      await tester.enterText(find.byKey(const Key('filter-device')), 'web');
      await tester.enterText(find.byKey(const Key('filter-from')), '2026-09-01');
      await tester.enterText(find.byKey(const Key('filter-to')), '2026-10-31');
      await tester.tap(find.byKey(const Key('filter-quality-ok')));
      await tester.tap(find.byKey(const Key('filter-synthetic')));
      await tester.pump();
      await show(tester);

      final sent = bed.analysis.requests.single;
      expect(sent.participant, 'P-001');
      expect(sent.protocolVersion, '2');
      expect(sent.device, 'web');
      expect(sent.from, '2026-09-01');
      expect(sent.to, '2026-10-31');
      expect(sent.qualities, {QualityGrade.review});
      expect(sent.includeSynthetic, isTrue);
    });

    testWidgets('choosing a path filter is sent', (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await openAnalysis(tester, bed);
      await tester.tap(find.byKey(const Key('filter-path')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interest conversation').last);
      await tester.pumpAndSettle();
      await show(tester);
      expect(bed.analysis.requests.single.path, 'interest_conversation');
    });

    testWidgets('bad dates are refused in the banner', (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await openAnalysis(tester, bed);
      await tester.enterText(find.byKey(const Key('filter-from')), 'soon');
      await tester.pump();
      await show(tester);
      expect(find.textContaining('"from" date'), findsOneWidget);
      expect(bed.analysis.requests, isEmpty);
    });

    testWidgets('shows the rows with the eye share change and its sign',
        (tester) async {
      useWindow(tester, 1440);
      await openAnalysis(tester, TestBed());
      await show(tester);
      expect(find.byKey(const Key('analysis-table')), findsOneWidget);
      expect(find.textContaining('4 sessions shown'), findsOneWidget);
      expect(find.textContaining('2 left out'), findsOneWidget);

      Text delta(String id) => tester.widget<Text>(
          find.descendant(of: find.byKey(Key('delta-$id')), matching: find.byType(Text)));
      expect(delta('5').data, '+12 pp');
      expect(delta('6').data, '-6 pp');
      expect(delta('7').data, 'Not evaluable');
      expect(delta('8').data, '0 pp');
      Color? tint(String id) => (tester.widget<Container>(find.byKey(Key('delta-$id'))).decoration
              as BoxDecoration)
          .color;
      expect(tint('5'), AppColors.successTint, reason: 'up');
      expect(tint('6'), AppColors.warningTint, reason: 'down');
      // Other fields of the row.
      expect(find.text('Faces v1 v2'), findsWidgets);
      expect(find.text('41 px'), findsOneWidget);
      expect(find.text('Cannot be judged'), findsWidgets);
    });

    testWidgets('lists the comparable groups with counts and the server note',
        (tester) async {
      useWindow(tester, 1440);
      await openAnalysis(tester, TestBed());
      await show(tester);
      await reveal(tester, const Key('groups-section'));
      expect(find.text('Comparable groups'), findsOneWidget);
      expect(find.byKey(const Key('group-web|2|l2cs-1|400')), findsOneWidget);
      expect(find.text('3 sessions · 1 participant'), findsOneWidget);
      expect(find.text('1 session · 1 participant'), findsOneWidget);
      expect(find.text('web · protocol v2 · l2cs-1 · 1280x720 · stimulus 400px'),
          findsWidgets);
      expect(find.byKey(const Key('groups-note')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('groups-note'))).data,
        'Sessions from different groups are never pooled into one trend by default.',
      );
    });

    testWidgets('one trend card per participant and group with a chart',
        (tester) async {
      useWindow(tester, 1440);
      await openAnalysis(tester, TestBed());
      await show(tester);
      await reveal(tester, const Key('trends-section'));
      final a = find.byKey(const Key('trend-P-001-web|2|l2cs-1|400'));
      final b = find.byKey(const Key('trend-P-002-android|1|l2cs-1|300'));
      expect(a, findsOneWidget);
      expect(b, findsOneWidget);
      expect(find.textContaining('3 sessions · 1 not evaluable (hollow)'), findsOneWidget);
      expect(find.byKey(const Key('trend-chart-P-001-web|2|l2cs-1|400')), findsOneWidget);
    });

    testWidgets('the chart paints hollow bars for not evaluable sessions',
        (tester) async {
      useWindow(tester, 800);
      await openAnalysis(tester, TestBed());
      await show(tester);
      await reveal(tester, const Key('trends-section'));
      final chart = find.byKey(const Key('trend-chart-P-001-web|2|l2cs-1|400'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      // Two sessions with values: four filled bars. One session without:
      // two outlined stubs. The order follows the dates (5, 6, 7).
      expect(
        tester.renderObject(chart),
        paints
          ..rect(style: PaintingStyle.fill) // session 5 baseline
          ..rect(style: PaintingStyle.fill) // session 5 post
          ..rect(style: PaintingStyle.fill) // session 6 baseline
          ..rect(style: PaintingStyle.fill) // session 6 post
          ..rect(style: PaintingStyle.stroke) // session 7 baseline, hollow
          ..rect(style: PaintingStyle.stroke), // session 7 post, hollow
      );
      // The other participant has no hollow bar.
      final other = find.byKey(const Key('trend-chart-P-002-android|1|l2cs-1|300'));
      await tester.ensureVisible(other);
      await tester.pumpAndSettle();
      expect(tester.renderObject(other), isNot(paints..rect(style: PaintingStyle.stroke)));
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('renders the whole result at ${width.toInt()} px', (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        await openAnalysis(tester, TestBed());
        await show(tester);
        expect(tester.takeException(), isNull);
        for (final key in ['groups-section', 'trends-section']) {
          await reveal(tester, Key(key));
          expect(tester.takeException(), isNull, reason: '$key at $width');
        }
        await reveal(tester, const Key('trend-P-001-web|2|l2cs-1|400'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an empty result says so', (tester) async {
      useWindow(tester, 800);
      final bed = TestBed(
        analysis: FakeAnalysisRepository(json: {
          'rows': <Object>[],
          'groups': <Object>[],
          'trends': <Object>[],
          'excluded': 3,
          'note': 'Nothing here.',
        }),
      );
      await openAnalysis(tester, bed);
      await show(tester);
      await reveal(tester, const Key('analysis-empty'));
      expect(find.byKey(const Key('analysis-empty')), findsOneWidget);
      await reveal(tester, const Key('analysis-summary'));
      expect(find.textContaining('3 left out'), findsOneWidget);
      expect(find.text('Nothing here.'), findsWidgets);
    });

    testWidgets('analysts can read and export too', (tester) async {
      useWindow(tester, 1440);
      await openAnalysis(tester, TestBed(), role: 'analyst');
      await show(tester);
      expect(find.byKey(const Key('analysis-table')), findsOneWidget);
      expect(find.byKey(const Key('export-sessions-csv')), findsOneWidget);
    });
  });

  group('exports on the Analysis tab', () {
    testWidgets('Sessions CSV and Sessions JSON download with the filters',
        (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await openAnalysis(tester, bed);
      await tester.enterText(find.byKey(const Key('filter-device')), 'web');
      await tester.pump();

      await tapVisible(tester, find.byKey(const Key('export-sessions-csv')));
      expect(bed.saver.saved.map((s) => s.name), ['sessions.csv']);
      expect(bed.exports.filters.single.device, 'web');
      expect(find.textContaining('Downloaded sessions.csv'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('export-sessions-json')));
      expect(bed.saver.saved.map((s) => s.name), ['sessions.csv', 'sessions.json']);
      expect(bed.saver.saved.last.type, 'application/json');
    });

    testWidgets('an export outside the browser explains itself', (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed(canSaveFiles: false);
      await openAnalysis(tester, bed);
      await tapVisible(tester, find.byKey(const Key('export-sessions-csv')));
      expect(find.textContaining('web app'), findsOneWidget);
    });

    testWidgets('the data dictionary opens in a dialog with name, type, unit, meaning',
        (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await openAnalysis(tester, bed);
      await tapVisible(tester, find.byKey(const Key('open-dictionary')));
      expect(find.text('Data dictionary'), findsWidgets);
      final table = find.byKey(const Key('dictionary-table'));
      expect(table, findsOneWidget);
      for (final header in ['Name', 'Type', 'Unit', 'Meaning']) {
        expect(find.descendant(of: table, matching: find.text(header)), findsOneWidget);
      }
      expect(find.text('eye_share'), findsOneWidget);
      expect(find.text('share 0-1'), findsOneWidget);
      expect(find.text('Share of classifiable time on the eye region.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-dictionary')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-table')), findsNothing);
    });

    testWidgets('the dictionary dialog fits a phone', (tester) async {
      useWindow(tester, 360, 740);
      await openAnalysis(tester, TestBed());
      await reveal(tester, const Key('open-dictionary'));
      await tester.tap(find.byKey(const Key('open-dictionary')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dictionary-table')), findsOneWidget);
    });
  });
}

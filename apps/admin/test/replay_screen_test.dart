import 'dart:ui' as ui;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/app_scope.dart';
import 'package:research_admin/features/replay/presentation/replay_canvas.dart';
import 'package:research_admin/features/replay/presentation/replay_screen.dart';
import 'package:research_admin/features/replay/presentation/replay_timeline.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> pumpReplay(WidgetTester tester, TestBed bed) async {
  await tester.pumpWidget(AppScope(
    dependencies: bed.dependencies,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const ReplayScreen(studyId: 1, sessionId: '21', participantCode: 'P-001'),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls the page until the widget with [key] is on screen.
Future<void> reveal(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key, skipOffstage: false));
  await tester.pumpAndSettle();
}

String timeText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('replay-time'))).data!;

void main() {
  group('replay painters', () {
    const screen = ScreenInfo(w: 1440, h: 900);
    const layout = StimulusLayout(
      screen: screen,
      faceBox: Box(500, 100, 440, 600),
      eyeRegion: Box(520, 220, 400, 120),
      mouthRegion: Box(560, 480, 320, 100),
    );

    test('the screen is scaled to fit, centred, aspect ratio kept', () {
      final wide = ScreenFit.of(const Size(800, 600), screen);
      expect(wide.rect.width / wide.rect.height, closeTo(1440 / 900, 1e-6));
      expect(wide.rect.left, greaterThanOrEqualTo(0));
      expect(wide.rect.right, lessThanOrEqualTo(800));
      expect(wide.rect.center.dx, closeTo(400, 1e-6));
      // A screen point lands inside the rectangle at the same proportion.
      final p = wide.point(720, 450);
      expect(p.dx, closeTo(wide.rect.center.dx, 1e-6));
      expect(p.dy, closeTo(wide.rect.center.dy, 1e-6));
      final tall = ScreenFit.of(const Size(200, 800), screen);
      expect(tall.rect.width, lessThanOrEqualTo(200));
      final box = wide.box(const Box(0, 0, 1440, 900));
      expect(box, wide.rect);
      // An unknown screen size does not divide by zero.
      final none = ScreenFit.of(const Size(100, 100), const ScreenInfo(w: 0, h: 0));
      expect(none.scale.isFinite, isTrue);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      test('the canvas paints without errors at ${width.toInt()} px', () {
        final size = Size(width, width * 0.625);
        for (final painter in [
          // Everything: layout, trial, trail and the current sample.
          ReplayCanvasPainter(
            screen: screen,
            positionMs: 2000,
            layout: layout,
            sample: const ReplaySample(tMs: 2000, x: 720, y: 300, conf: 0.9, regionCode: 0),
            trail: [
              for (var t = 1500; t <= 2000; t += 100)
                ReplaySample(tMs: t, x: 700 + (t - 1500) / 10, y: 300),
            ],
            trial: const ReplayTrial(
              stageIndex: 0,
              trialIndex: 0,
              tMs: 1500,
              numberShown: '42',
              x: 200,
              y: 150,
            ),
          ),
          // Nothing: no layout, no sample.
          ReplayCanvasPainter(screen: screen, positionMs: 0),
          // An uncertain sample (no x, y) and a trial without a position.
          ReplayCanvasPainter(
            screen: screen,
            positionMs: 5,
            layout: layout,
            sample: const ReplaySample(tMs: 5),
            trial: const ReplayTrial(stageIndex: 0, trialIndex: 0, tMs: 0, numberShown: '7'),
          ),
          // Gaze far outside the screen.
          ReplayCanvasPainter(
            screen: screen,
            positionMs: 9,
            layout: layout,
            sample: const ReplaySample(tMs: 9, x: -400, y: 5000),
          ),
        ]) {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), size);
          recorder.endRecording();
        }
      });

      test('the timeline paints without errors at ${width.toInt()} px', () {
        final bundle = ReplayBundle.fromJson(sampleReplayJson());
        final recorder = ui.PictureRecorder();
        ReplayTimelinePainter(bundle: bundle, positionMs: 12345)
            .paint(Canvas(recorder), Size(width, TimelineMetrics.height));
        recorder.endRecording();
        // A bundle without anything at all.
        final empty = ReplayBundle.fromJson({});
        ReplayTimelinePainter(bundle: empty, positionMs: 0)
            .paint(Canvas(ui.PictureRecorder()), Size(width, TimelineMetrics.height));
      });
    }
  });

  group('replay screen', () {
    testWidgets('opens from the session detail with the Replay button',
        (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await openStudy(tester, bed, role: 'researcher');
      await openTab(tester, 'Sessions');
      await tester.tap(find.text('P-001'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-replay')));
      await tester.pumpAndSettle();
      expect(find.text('Replay of P-001'), findsOneWidget);
      expect(bed.replay.loaded, ['1/21']);
      expect(find.byKey(const Key('replay-canvas')), findsOneWidget);
    });

    testWidgets('says that no participant video exists and that nothing is smoothed',
        (tester) async {
      useWindow(tester, 1440);
      await pumpReplay(tester, TestBed());
      expect(find.text('No participant video exists'), findsOneWidget);
      expect(find.text('Display only; no smoothing'), findsOneWidget);
      // The quality grade and the estimator are visible too.
      expect(find.text('Review'), findsOneWidget);
      expect(find.byKey(const Key('synthetic-badge')), findsOneWidget);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('renders and plays at ${width.toInt()} px without overflow',
          (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        await pumpReplay(tester, TestBed());
        expect(tester.takeException(), isNull);
        for (final key in ['replay-canvas', 'replay-scrubber', 'replay-speed']) {
          expect(find.byKey(Key(key), skipOffstage: false), findsOneWidget);
        }
        await reveal(tester, const Key('replay-play'));

        await tester.tap(find.byKey(const Key('replay-play')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(tester.widget<Text>(find.byKey(const Key('replay-time'))).data,
            isNot('00:00.000'));
        // Stop the ticker before the test ends.
        await tester.tap(find.byKey(const Key('replay-play')));
        await tester.pump();
      });
    }

    testWidgets('the arrow keys step 100 ms', (tester) async {
      useWindow(tester, 1440);
      await pumpReplay(tester, TestBed());
      expect(timeText(tester), '00:00.000');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(timeText(tester), '00:00.300');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(timeText(tester), '00:00.200');
    });

    testWidgets('the step buttons do the same as the arrow keys', (tester) async {
      useWindow(tester, 1440);
      await pumpReplay(tester, TestBed());
      await tester.tap(find.byKey(const Key('replay-step-forward')));
      await tester.tap(find.byKey(const Key('replay-step-forward')));
      await tester.pump();
      expect(timeText(tester), '00:00.200');
      await tester.tap(find.byKey(const Key('replay-step-back')));
      await tester.pump();
      expect(timeText(tester), '00:00.100');
    });

    testWidgets('tapping the scrubber jumps there; the region and trial follow',
        (tester) async {
      useWindow(tester, 1440);
      await pumpReplay(tester, TestBed());
      final box = tester.getRect(find.byKey(const Key('replay-scrubber')));
      // 13.5 s of 30 s: the first number (42) is on screen, practice segment.
      await tester.tapAt(Offset(box.left + box.width * 13500 / 30000, box.center.dy));
      await tester.pump();
      expect(timeText(tester), '00:13.500');
      expect(find.text('Segment: practice'), findsOneWidget);
      expect(find.text('Gaze: Mouth'), findsOneWidget);
      expect(find.textContaining('Number shown: 42'), findsOneWidget);

      // In the gap between 9.2 and 11.9 s: no sample, and it says so.
      await tester.tapAt(Offset(box.left + box.width * 10500 / 30000, box.center.dy));
      await tester.pump();
      expect(find.byKey(const Key('replay-gap')), findsOneWidget);
      expect(find.text('Gaze: No samples (gap)'), findsOneWidget);

      // In the pause at 21 s.
      await tester.tapAt(Offset(box.left + box.width * 21000 / 30000, box.center.dy));
      await tester.pump();
      expect(find.byKey(const Key('replay-paused')), findsOneWidget);
    });

    testWidgets('dragging the scrubber follows the pointer', (tester) async {
      useWindow(tester, 1440);
      await pumpReplay(tester, TestBed());
      final box = tester.getRect(find.byKey(const Key('replay-scrubber')));
      await tester.dragFrom(
        Offset(box.left + 2, box.center.dy),
        Offset(box.width / 2, 0),
      );
      await tester.pump();
      final text = timeText(tester);
      expect(text, startsWith('00:1'), reason: 'about the middle of 30 s: $text');
    });

    testWidgets('the speed can be set to 0.5x, 1x and 2x', (tester) async {
      useWindow(tester, 1440);
      await pumpReplay(tester, TestBed());
      expect(find.text('0.5×'), findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
      await tester.tap(find.text('2×'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('replay-play')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      // Two frames of 500 ms at 2x.
      expect(timeText(tester), '00:02.000');
      await tester.tap(find.byKey(const Key('replay-play')));
      await tester.pump();
    });

    testWidgets('the canvas draws the layout, the gaze dot and the trial number',
        (tester) async {
      useWindow(tester, 1440);
      await pumpReplay(tester, TestBed());
      final canvas = find.byKey(const Key('replay-canvas'));
      // Baseline, a sample with a position: layout rectangles and a dot.
      final box = tester.getRect(find.byKey(const Key('replay-scrubber')));
      await tester.tapAt(Offset(box.left + box.width * 5000 / 30000, box.center.dy));
      await tester.pump();
      expect(
        tester.renderObject(canvas),
        paints
          ..rect() // the surroundings
          ..rect() // the screen
          ..rect(style: PaintingStyle.fill) // face
          ..rect(style: PaintingStyle.stroke)
          ..circle(),
      );
      // In the gap nothing is drawn as the gaze.
      await tester.tapAt(Offset(box.left + box.width * 10500 / 30000, box.center.dy));
      await tester.pump();
      expect(tester.renderObject(canvas), isNot(paints..circle()));
    });

    testWidgets('a failed load shows the message and a retry', (tester) async {
      useWindow(tester, 800);
      final bed = TestBed(
        replay: FakeReplayRepository()
          ..failure = const ApiException('Not a member of this study.', statusCode: 403),
      );
      await pumpReplay(tester, bed);
      expect(find.text('Not a member of this study.'), findsOneWidget);
      bed.replay.failure = null;
      await tester.tap(find.byKey(const Key('retry-replay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replay-canvas')), findsOneWidget);
    });

    testWidgets('a session without samples says so and still shows the screen',
        (tester) async {
      useWindow(tester, 800);
      final json = sampleReplayJson(withMedia: false)
        ..['samples'] = <Object>[]
        ..['layouts'] = <Object>[];
      await pumpReplay(tester, TestBed(replay: FakeReplayRepository(json: json)));
      expect(find.textContaining('no stored samples'), findsOneWidget);
      expect(find.byKey(const Key('replay-canvas')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('stimulus video', () {
    testWidgets('a panel with the video appears when the session played clips',
        (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await pumpReplay(tester, bed);
      expect(find.byKey(const Key('replay-stimulus')), findsOneWidget);
      expect(find.text('Stimulus video'), findsOneWidget);
      expect(find.byKey(const Key('fake-video')), findsOneWidget);
      expect(find.text('/media/tok1'), findsOneWidget, reason: 'the first clip is loaded');
      expect(find.textContaining('No clip plays at this time'), findsOneWidget);
    });

    testWidgets('a clip whose file the server could not name says so',
        (tester) async {
      useWindow(tester, 1440);
      final json = sampleReplayJson();
      json['media'] = [
        {'segment_id': 's1', 'media_key': 's1', 'start_ms': 12000, 'url': null},
      ];
      final bed = TestBed(replay: FakeReplayRepository(json: json));
      await pumpReplay(tester, bed);
      expect(find.byKey(const Key('replay-stimulus')), findsOneWidget);
      expect(find.byKey(const Key('replay-media-missing')), findsOneWidget);
      expect(find.byKey(const Key('fake-video')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no panel without clips', (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed(
        replay: FakeReplayRepository(json: sampleReplayJson(withMedia: false)),
      );
      await pumpReplay(tester, bed);
      expect(find.byKey(const Key('replay-stimulus')), findsNothing);
      expect(find.text('Stimulus video'), findsNothing);
    });

    testWidgets('the video follows the scrubber inside a clip and plays with the timeline',
        (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await pumpReplay(tester, bed);
      final box = tester.getRect(find.byKey(const Key('replay-scrubber')));
      bed.videoPlayer.commands.clear();

      // 15.0 s: 3.0 s into the clip that started at 12.0 s.
      await tester.tapAt(Offset(box.left + box.width * 15000 / 30000, box.center.dy));
      await tester.pump();
      expect(bed.videoPlayer.commands, contains('seek:3.00'));
      expect(find.textContaining('Clip s1.webm of segment s1, 3.0 s in.'), findsOneWidget);

      // Playing plays the clip; pausing pauses it.
      bed.videoPlayer.commands.clear();
      await tester.tap(find.byKey(const Key('replay-play')));
      await tester.pump();
      expect(bed.videoPlayer.commands, contains('play'));
      await tester.tap(find.byKey(const Key('replay-play')));
      await tester.pump();
      expect(bed.videoPlayer.commands.last, 'pause');

      // Into the second clip: its link is loaded.
      await tester.tapAt(Offset(box.left + box.width * 23000 / 30000, box.center.dy));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('/media/tok2'), findsOneWidget);
      expect(find.textContaining('Clip s2.webm'), findsOneWidget);
    });

    testWidgets('a fast drag sends the video at most 4 seeks in a second',
        (tester) async {
      useWindow(tester, 1440);
      final bed = TestBed();
      await pumpReplay(tester, bed);
      final box = tester.getRect(find.byKey(const Key('replay-scrubber')));
      bed.videoPlayer.commands.clear();
      // Wall-clock throttle: this whole drag happens within a few ms.
      final gesture = await tester.startGesture(
        Offset(box.left + box.width * 13000 / 30000, box.center.dy),
      );
      for (var i = 1; i <= 30; i++) {
        await gesture.moveTo(
          Offset(box.left + box.width * (13000 + i * 100) / 30000, box.center.dy),
        );
      }
      await gesture.up();
      await tester.pump();
      final seeks = bed.videoPlayer.commands.where((c) => c.startsWith('seek:')).length;
      expect(seeks, lessThanOrEqualTo(2),
          reason: '30 scrubber events in a few ms: the first goes out, the '
              'rest wait for the next 250 ms slot');
      // Let the pending trailing timer run so the test ends cleanly.
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}

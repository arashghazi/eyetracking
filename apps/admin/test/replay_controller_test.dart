import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/replay/application/replay_controller.dart';

import 'fakes.dart';

/// A controller on the sample replay with a hand-driven clock and timers.
class Rig {
  Rig({Map<String, dynamic>? json})
      : repo = FakeReplayRepository(json: json ?? sampleReplayJson()) {
    controller = ReplayController(
      repo,
      1,
      '21',
      video: video,
      clockMs: () => now,
      schedule: (d, f) {
        final t = FakeTimer(d, f, now + d.inMilliseconds);
        timers.add(t);
        return t;
      },
    );
    video.attach(player);
  }

  final FakeReplayRepository repo;
  final VideoStageController video = VideoStageController();
  final RecordingVideoPlayer player = RecordingVideoPlayer();
  final List<FakeTimer> timers = [];
  int now = 100000;
  late final ReplayController controller;

  List<String> get seeks =>
      [for (final c in player.commands) if (c.startsWith('seek:')) c];
}

class FakeTimer implements Timer {
  FakeTimer(this.duration, this._callback, this.dueAtMs);

  final Duration duration;
  final int dueAtMs;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}

void main() {
  group('loading', () {
    test('loads the bundle and starts paused at zero', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      expect(c.bundle, isNull);
      await c.load();
      expect(rig.repo.loaded, ['1/21']);
      expect(c.bundle, isNotNull);
      expect(c.positionMs, 0);
      expect(c.playing, isFalse);
      expect(c.durationMs, 30000);
      expect(c.error, isNull);
    });

    test('a failed load shows the message and can be retried', () async {
      final rig = Rig();
      rig.repo.failure = const ApiException('Not a member of this study.', statusCode: 403);
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      expect(c.bundle, isNull);
      expect(c.error, 'Not a member of this study.');
      rig.repo.failure = null;
      await c.load();
      expect(c.bundle, isNotNull);
      expect(c.error, isNull);
    });
  });

  group('time stepping', () {
    test('steps by 100 ms, clamped to the session', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.step(ReplayController.stepMs);
      expect(c.positionMs, 100);
      c.step(ReplayController.stepMs);
      c.step(ReplayController.stepMs);
      expect(c.positionMs, 300);
      c.step(-ReplayController.stepMs);
      expect(c.positionMs, 200);
      c.step(-5000);
      expect(c.positionMs, 0, reason: 'not before the start');
      c.seek(1000000);
      expect(c.positionMs, 30000, reason: 'not after the end');
      expect(c.atEnd, isTrue);
    });

    test('advance moves the position by the elapsed time times the speed',
        () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.advance(const Duration(milliseconds: 500));
      expect(c.positionMs, 0, reason: 'nothing moves while paused');

      c.play();
      c.advance(const Duration(milliseconds: 250));
      expect(c.positionMs, 250);
      c.setSpeed(2);
      c.advance(const Duration(milliseconds: 250));
      expect(c.positionMs, 750);
      c.setSpeed(0.5);
      c.advance(const Duration(milliseconds: 1000));
      expect(c.positionMs, 1250);
      c.setSpeed(3); // not on offer: ignored
      expect(c.speed, 0.5);
    });

    test('stops at the end and plays again from the start', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.seek(29900);
      c.play();
      c.advance(const Duration(milliseconds: 500));
      expect(c.positionMs, 30000);
      expect(c.playing, isFalse);
      c.play();
      expect(c.positionMs, 0, reason: 'play at the end starts over');
      expect(c.playing, isTrue);
      c.pause();
      expect(c.playing, isFalse);
      c.toggle();
      expect(c.playing, isTrue);
    });
  });

  group('what is true at the current time', () {
    test('the active layout follows the time and the segment', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      expect(c.activeLayout, isNull, reason: 'before the first segment');
      c.seek(5000);
      expect(c.activeLayout!.segment, 'baseline');
      expect(c.activeSegment!.label, 'baseline');
      c.seek(11500);
      expect(c.activeLayout, isNull, reason: 'between segments');
      c.seek(12000);
      expect(c.activeLayout!.stageIndex, 0);
      expect(c.activeLayout!.layout.eyeRegion.w, 400);
    });

    test('the active trial is the number on screen', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.seek(12999);
      expect(c.activeTrial, isNull);
      c.seek(13000);
      expect(c.activeTrial!.numberShown, '42');
      c.seek(14499);
      expect(c.activeTrial!.numberShown, '42');
      c.seek(14500);
      expect(c.activeTrial, isNull, reason: 'answered after 1500 ms');
      c.seek(16000);
      expect(c.activeTrial!.numberShown, '17');
      c.seek(24000);
      expect(c.activeTrial, isNull, reason: 'unanswered: ends after 8 s');
    });

    test('gaps and pauses are found by time; a gap has no sample', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.seek(9000);
      expect(c.activeGap, isNull);
      expect(c.currentSample!.tMs, 9000);
      c.seek(9500);
      expect(c.activeGap, isNotNull);
      expect(c.currentSample, isNull);
      expect(c.regionText, 'No samples (gap)');
      c.seek(11900);
      expect(c.activeGap, isNull);
      c.seek(20400);
      expect(c.activePause, isNull);
      c.seek(20500);
      expect(c.activePause, isNotNull);
      c.seek(22000);
      expect(c.activePause, isNull);
    });

    test('the current sample names its region; uncertain draws nothing', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.seek(1200);
      expect(c.currentSample!.regionCode, ReplayRegion.eye);
      expect(c.regionText, 'Eyes');
      c.seek(1100);
      expect(c.regionText, 'Rest of the face');
      c.seek(9100);
      final s = c.currentSample!;
      expect(s.hasPosition, isFalse, reason: 'null x and y: nothing to draw');
      expect(c.regionText, 'Not sure');
      expect(c.trail.any((t) => t.tMs == 9100), isFalse);
    });

    test('the trail is the last 500 ms with a position, oldest first', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.seek(2000);
      expect([for (final s in c.trail) s.tMs],
          [1500, 1600, 1700, 1800, 1900, 2000]);
      c.seek(1050);
      expect([for (final s in c.trail) s.tMs], [1000]);
      c.seek(500);
      expect(c.trail, isEmpty);
      c.seek(9300);
      expect([for (final s in c.trail) s.tMs], [8800, 8900, 9000],
          reason: 'the uncertain sample and the gap draw nothing');
      c.seek(9000);
      expect(c.trail.last.tMs, 9000);
    });
  });

  group('stimulus video', () {
    test('the clip is found by time and the seconds are counted from its start',
        () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      expect(c.activeMedia, isNull);
      expect(c.mediaSeconds, isNull);
      expect(c.stageMedia!.mediaKey, 's1.webm', reason: 'the first clip is loaded');
      c.seek(15500);
      expect(c.activeMedia!.mediaKey, 's1.webm');
      expect(c.mediaSeconds, 3.5);
      c.seek(22000);
      expect(c.activeMedia!.mediaKey, 's2.webm');
      expect(c.mediaSeconds, 0);
      c.seek(11000);
      expect(c.activeMedia, isNull);
      expect(c.stageMedia!.mediaKey, 's2.webm', reason: 'the last clip stays loaded');
    });

    test('scrubbing inside a clip seeks it; playing plays it; pausing pauses it',
        () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      rig.player.commands.clear();
      c.seek(15000);
      expect(rig.seeks, ['seek:3.00']);
      c.play();
      expect(rig.player.commands.last, 'play');
      c.pause();
      expect(rig.player.commands.last, 'pause');
      c.setSpeed(2);
      expect(rig.player.commands.last, 'rate:2.0');
    });

    test('leaving a clip pauses the video, entering one seeks to its start',
        () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      c.seek(11000);
      rig.player.commands.clear();
      c.play();
      expect(rig.player.commands, ['pause'], reason: 'no clip yet');
      // Enter the first clip by playing on.
      rig.now += 1000;
      c.advance(const Duration(milliseconds: 1000));
      expect(c.activeMedia!.mediaKey, 's1.webm');
      expect(rig.player.commands, ['pause', 'seek:0.00', 'play']);
    });

    test('a replay without clips never touches the video', () async {
      final rig = Rig(json: sampleReplayJson(withMedia: false));
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      rig.player.commands.clear();
      c.seek(15000);
      c.play();
      c.advance(const Duration(seconds: 1));
      expect(rig.seeks, isEmpty);
      expect(c.stageMedia, isNull);
      expect(c.videoSeeks, 0);
    });
  });

  group('seek throttling', () {
    test('at most 4 seeks per second: the first goes at once, a burst is held',
        () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      rig.player.commands.clear();
      final before = c.videoSeeks;

      c.seek(15000);
      expect(c.videoSeeks, before + 1, reason: 'the first seek goes at once');

      // A drag: many seeks inside 250 ms; none of them reaches the video.
      for (var i = 1; i <= 20; i++) {
        rig.now += 10;
        c.seek(15000 + i * 50);
      }
      expect(c.videoSeeks, before + 1);
      expect(rig.timers.where((t) => t.isActive).length, 1,
          reason: 'one trailing seek is scheduled, not one per event');

      // The trailing seek goes out with the position as it is by then.
      rig.now += 60;
      rig.timers.firstWhere((t) => t.isActive).fire();
      expect(c.videoSeeks, before + 2);
      expect(rig.seeks.last, 'seek:4.00', reason: '16.0 s minus the 12.0 s start');
    });

    test('seeks 250 ms apart all go out', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      final before = c.videoSeeks;
      for (var i = 0; i < 8; i++) {
        c.seek(13000 + i * 100);
        rig.now += 250;
      }
      expect(c.videoSeeks - before, 8);
    });

    test('over one second no more than 4 seeks are sent', () async {
      final rig = Rig();
      final c = rig.controller;
      addTearDown(c.dispose);
      await c.load();
      final before = c.videoSeeks;
      final start = rig.now;
      // A fast drag: one scrubber event every 10 ms for a second, with the
      // timers firing when they fall due.
      for (var t = 0; t < 1000; t += 10) {
        rig.now = start + t;
        for (final timer in rig.timers.where((x) => x.isActive)) {
          if (timer.dueAtMs <= rig.now) timer.fire();
        }
        c.seek(13000 + t * 5);
      }
      expect(c.videoSeeks - before, inInclusiveRange(3, 4));
    });

    test('a trailing seek is dropped when the controller is disposed', () async {
      final rig = Rig();
      final c = rig.controller;
      await c.load();
      c.seek(15000);
      rig.now += 10;
      c.seek(15100);
      final timer = rig.timers.firstWhere((t) => t.isActive);
      c.dispose();
      expect(timer.cancelled, isTrue);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'video_stage_config.dart';
import 'video_stage_controller.dart';

/// A [VideoStagePlayer] that only records the commands it gets, for tests
/// of anything that drives a [VideoStageController].
class RecordingVideoPlayer implements VideoStagePlayer {
  final List<String> commands = [];

  @override
  void seek(double seconds) => commands.add('seek:${seconds.toStringAsFixed(2)}');

  @override
  void play() => commands.add('play');

  @override
  void pause() => commands.add('pause');

  @override
  void setRate(double rate) => commands.add('rate:$rate');
}

/// Test double for the video player: "plays" for [duration], then ends. A URL
/// in [failUrls] fails instead (once per entry removed from the set when
/// [failOnce] is true).
class FakeVideoStage extends StatefulWidget {
  const FakeVideoStage({
    super.key,
    required this.config,
    this.duration = const Duration(milliseconds: 50),
    this.intrinsic = const Size(1920, 1080),
    this.failUrls,
    this.failOnce = false,
    this.player,
  });

  final VideoStageConfig config;
  final Duration duration;

  /// Pixel size the fake video pretends to have (letterboxing follows).
  final Size intrinsic;
  final Set<String>? failUrls;
  final bool failOnce;

  /// Records what the config's controller asks of the player.
  final RecordingVideoPlayer? player;

  /// A [VideoStageBuilder] for `AppDependencies` in tests.
  static VideoStageBuilder builder({
    Duration duration = const Duration(milliseconds: 50),
    Size intrinsic = const Size(1920, 1080),
    Set<String>? failUrls,
    bool failOnce = false,
    RecordingVideoPlayer? player,
  }) =>
      (context, config) => FakeVideoStage(
            config: config,
            duration: duration,
            intrinsic: intrinsic,
            failUrls: failUrls,
            failOnce: failOnce,
            player: player,
          );

  @override
  State<FakeVideoStage> createState() => _FakeVideoStageState();
}

class _FakeVideoStageState extends State<FakeVideoStage> {
  Timer? _timer;
  VideoStagePlayer? _attached;

  @override
  void initState() {
    super.initState();
    final controller = widget.config.controller;
    final player = widget.player;
    if (controller != null && player != null) {
      _attached = player;
      controller.attach(player);
    }
    _start();
  }

  @override
  void didUpdateWidget(FakeVideoStage old) {
    super.didUpdateWidget(old);
    if (old.config.url != widget.config.url) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final attached = _attached;
    if (attached != null) widget.config.controller?.detach(attached);
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    final fails = widget.failUrls;
    if (fails != null && fails.contains(widget.config.url)) {
      if (widget.failOnce) fails.remove(widget.config.url);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.config.onError?.call('The video could not be loaded.');
      });
      return;
    }
    if (!widget.config.autoplay) {
      // Waits for its controller: loaded, but nothing plays by itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.config.controller?.applyPending();
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.config.onPlaying?.call();
    });
    _timer = Timer(widget.duration, () {
      if (mounted) widget.config.onEnded?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return VideoRectReporter(
      intrinsic: widget.intrinsic,
      onRect: widget.config.onRect,
      child: ColoredBox(
        key: const Key('fake-video'),
        color: const Color(0xFF1B2A2A),
        child: Center(
          child: Text(
            widget.config.url,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

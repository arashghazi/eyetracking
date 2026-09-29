import 'dart:async';

import 'package:flutter/material.dart';

import 'video_stage_config.dart';

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
  });

  final VideoStageConfig config;
  final Duration duration;

  /// Pixel size the fake video pretends to have (letterboxing follows).
  final Size intrinsic;
  final Set<String>? failUrls;
  final bool failOnce;

  /// A [VideoStageBuilder] for `AppDependencies` in tests.
  static VideoStageBuilder builder({
    Duration duration = const Duration(milliseconds: 50),
    Size intrinsic = const Size(1920, 1080),
    Set<String>? failUrls,
    bool failOnce = false,
  }) =>
      (context, config) => FakeVideoStage(
            config: config,
            duration: duration,
            intrinsic: intrinsic,
            failUrls: failUrls,
            failOnce: failOnce,
          );

  @override
  State<FakeVideoStage> createState() => _FakeVideoStageState();
}

class _FakeVideoStageState extends State<FakeVideoStage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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

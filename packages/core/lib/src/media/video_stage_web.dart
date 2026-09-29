// Web-only video player. Loaded through a conditional import, so it is never
// compiled for the VM or Android.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'video_stage_config.dart';
import 'video_stage_controller.dart';

/// Plays one segment in a browser `<video>` element (`object-fit: contain`)
/// placed with [HtmlElementView], like the camera preview. It reports the
/// end of the video, failures and the rectangle the picture really occupies.
class VideoStage extends StatefulWidget {
  const VideoStage({super.key, required this.config});

  final VideoStageConfig config;

  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> implements VideoStagePlayer {
  /// A video that shows no picture within this time counts as not ready.
  static const _startTimeout = Duration(seconds: 20);

  web.HTMLVideoElement? _video;
  Size? _intrinsic;
  bool _needsTap = false;
  Timer? _watchdog;
  String? _loadedUrl;

  late final JSFunction _onEnded = ((web.Event _) => _handleEnded()).toJS;
  late final JSFunction _onError = ((web.Event _) => _handleError()).toJS;
  late final JSFunction _onMeta = ((web.Event _) => _handleMetadata()).toJS;
  late final JSFunction _onPlaying = ((web.Event _) => _handlePlaying()).toJS;

  @override
  void didUpdateWidget(VideoStage old) {
    super.didUpdateWidget(old);
    if (!identical(old.config.controller, widget.config.controller)) {
      old.config.controller?.detach(this);
      widget.config.controller?.attach(this);
    }
    if (old.config.url != widget.config.url) _load();
  }

  // The remote control of the replay (seek, play, pause, speed).
  @override
  void seek(double seconds) {
    final video = _video;
    if (video != null && seconds.isFinite) video.currentTime = seconds;
  }

  @override
  void play() => _play(quiet: true);

  @override
  void pause() => _video?.pause();

  @override
  void setRate(double rate) {
    final video = _video;
    if (video != null && rate > 0) video.playbackRate = rate;
  }

  @override
  void dispose() {
    widget.config.controller?.detach(this);
    _watchdog?.cancel();
    final video = _video;
    if (video != null) {
      video.removeEventListener('ended', _onEnded);
      video.removeEventListener('error', _onError);
      video.removeEventListener('loadedmetadata', _onMeta);
      video.removeEventListener('playing', _onPlaying);
      video.pause();
      // Releases the connection to the media server.
      video.removeAttribute('src');
      video.load();
    }
    super.dispose();
  }

  void _attach(web.HTMLVideoElement video) {
    _video = video
      ..controls = false
      ..muted = false
      ..autoplay = false
      ..playsInline = true
      ..preload = 'auto';
    video.style.cssText = 'width:100%;height:100%;object-fit:contain;'
        'background:#000;border:0;';
    video.addEventListener('ended', _onEnded);
    video.addEventListener('error', _onError);
    video.addEventListener('loadedmetadata', _onMeta);
    video.addEventListener('playing', _onPlaying);
    widget.config.controller?.attach(this);
    _load();
  }

  void _load() {
    final video = _video;
    if (video == null) return;
    _watchdog?.cancel();
    _intrinsic = null;
    _needsTap = false;
    _loadedUrl = widget.config.url;
    video.src = widget.config.url;
    video.load();
    if (!widget.config.autoplay) {
      // A remote-controlled player waits for its controller; it is ready
      // when the metadata is in (see [_handleMetadata]).
      return;
    }
    _watchdog = Timer(_startTimeout, () {
      if (!mounted) return;
      widget.config.onError?.call('The video did not start in time.');
    });
    _play();
  }

  void _play({bool quiet = false}) {
    final video = _video;
    if (video == null) return;
    video.play().toDart.then((_) {}, onError: (Object e) {
      // Browsers may refuse to start with sound until the person taps.
      if (quiet || !mounted || _loadedUrl != widget.config.url) return;
      if (e.toString().contains('NotAllowed')) {
        _watchdog?.cancel();
        setState(() => _needsTap = true);
      }
    });
  }

  void _handleEnded() {
    if (mounted) widget.config.onEnded?.call();
  }

  void _handleError() {
    if (!mounted) return;
    _watchdog?.cancel();
    widget.config.onError?.call('The video could not be loaded.');
  }

  void _handleMetadata() {
    final video = _video;
    if (!mounted || video == null) return;
    if (video.videoWidth > 0 && video.videoHeight > 0) {
      setState(() => _intrinsic = Size(
            video.videoWidth.toDouble(),
            video.videoHeight.toDouble(),
          ));
    }
    widget.config.controller?.applyPending();
  }

  void _handlePlaying() {
    if (!mounted) return;
    _watchdog?.cancel();
    if (_needsTap) setState(() => _needsTap = false);
    widget.config.onPlaying?.call();
  }

  @override
  Widget build(BuildContext context) {
    return VideoRectReporter(
      intrinsic: _intrinsic,
      onRect: widget.config.onRect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          HtmlElementView.fromTagName(
            tagName: 'video',
            onElementCreated: (Object element) =>
                _attach(element as web.HTMLVideoElement),
          ),
          if (_needsTap)
            Center(
              child: FilledButton.icon(
                key: const Key('video-tap-to-play'),
                onPressed: _play,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play the video'),
              ),
            ),
        ],
      ),
    );
  }
}

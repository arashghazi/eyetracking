import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// One camera frame encoded as JPEG. Frames are only ever sent to the gaze
/// estimator and are never stored.
class CapturedFrame {
  const CapturedFrame({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.tMs,
  });

  final Uint8List jpeg;
  final int width;
  final int height;

  /// Monotonic milliseconds from the session clock (see [FrameSource.clock]).
  final int tMs;
}

/// Something in the environment changed that makes a calibration invalid.
enum FrameSourceEvent {
  cameraChanged('camera_changed'),
  orientationChanged('orientation_changed'),

  /// Browser zoom: `window.devicePixelRatio` changed.
  zoomChanged('zoom_changed');

  const FrameSourceEvent(this.wire);

  /// Session event type the server expects.
  final String wire;
}

/// The camera could not be used; [message] is safe to show.
class FrameSourceException implements Exception {
  const FrameSourceException(this.message);

  final String message;

  @override
  String toString() => 'FrameSourceException: $message';
}

/// Port for camera capture. `WebFrameSource` implements it for PC web;
/// Android arrives later. All timestamps use [clock], a Stopwatch that the
/// session restarts when it is created, so frames and session events share
/// one monotonic time base.
abstract class FrameSource {
  /// Monotonic session clock in milliseconds.
  final Stopwatch clock = Stopwatch();

  int get nowMs {
    if (!clock.isRunning) clock.start();
    return clock.elapsedMilliseconds;
  }

  /// Zeroes and starts the session clock. Called once per session.
  void restartClock() => clock
    ..reset()
    ..start();

  /// Opens the camera. Throws [FrameSourceException] when access is denied
  /// or no camera exists, and [UnsupportedError] on platforms without capture.
  Future<void> start({int width = 640, int height = 480});

  /// JPEG frames at about [fps] while listened to; cancelling the
  /// subscription stops capturing but keeps the camera open.
  Stream<CapturedFrame> frames({double fps = 10});

  /// Releases the camera.
  Future<void> stop();

  bool get isActive;

  /// Names of the cameras the browser reports (empty until permission).
  List<String> get cameraLabels;

  /// Label of the camera in use, if known.
  String? get activeCameraLabel;

  /// Resolution actually delivered, 0 before [start].
  int get frameWidth;
  int get frameHeight;

  /// Camera, orientation and zoom changes. Broadcast stream.
  Stream<FrameSourceEvent> get events;

  /// Live preview of the camera for the participant to position themself.
  Widget preview();
}

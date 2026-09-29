import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'frame_source.dart';

/// In-memory [FrameSource] for tests. Frames are either generated at a fixed
/// [interval] while [autoFrames] is on, or pushed by hand with [emit].
class FakeFrameSource extends FrameSource {
  FakeFrameSource({
    this.autoFrames = true,
    this.interval = const Duration(milliseconds: 5),
    this.labels = const ['Fake camera'],
  });

  /// Generate frames automatically while somebody listens.
  bool autoFrames;
  Duration interval;
  final List<String> labels;

  /// When set, [start] throws it.
  Object? startError;

  int startCount = 0;
  int stopCount = 0;
  int listenCount = 0;
  bool _active = false;
  StreamController<CapturedFrame>? _frames;
  final _events = StreamController<FrameSourceEvent>.broadcast(sync: true);

  /// True while somebody is subscribed to [frames].
  bool get streaming => _frames?.hasListener ?? false;

  @override
  bool get isActive => _active;

  @override
  Future<void> start({int width = 640, int height = 480}) async {
    if (startError != null) throw startError!;
    startCount++;
    _active = true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _active = false;
  }

  @override
  Stream<CapturedFrame> frames({double fps = 10}) {
    Timer? timer;
    late final StreamController<CapturedFrame> controller;
    controller = StreamController<CapturedFrame>(
      onListen: () {
        listenCount++;
        if (autoFrames) {
          timer = Timer.periodic(interval, (_) => controller.add(_frame()));
        }
      },
      onCancel: () => timer?.cancel(),
    );
    _frames = controller;
    return controller.stream;
  }

  CapturedFrame _frame([int? tMs]) => CapturedFrame(
        jpeg: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
        width: 640,
        height: 480,
        tMs: tMs ?? nowMs,
      );

  /// Pushes one frame to the current listener (manual mode).
  void emit({int? tMs}) => _frames?.add(_frame(tMs));

  /// Simulates a camera, orientation or zoom change.
  void emitEvent(FrameSourceEvent event) => _events.add(event);

  @override
  List<String> get cameraLabels => labels;

  @override
  String? get activeCameraLabel => labels.isEmpty ? null : labels.first;

  @override
  int get frameWidth => 640;

  @override
  int get frameHeight => 480;

  @override
  Stream<FrameSourceEvent> get events => _events.stream;

  @override
  Widget preview() => const ColoredBox(
        key: Key('fake-camera-preview'),
        color: Color(0xFF223333),
        child: Center(child: Text('Camera preview')),
      );
}

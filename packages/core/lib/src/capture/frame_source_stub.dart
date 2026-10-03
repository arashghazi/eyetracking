import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/session.dart';
import 'frame_source.dart';

/// Non-web platforms cannot capture yet: every use of the camera throws.
class WebFrameSource extends FrameSource {
  @override
  Future<void> start({int width = 640, int height = 480}) => throw UnsupportedError(
      'Camera capture is available on PC web first; Android arrives later');

  @override
  Stream<CapturedFrame> frames({double fps = 10}) => throw UnsupportedError(
      'Camera capture is available on PC web first; Android arrives later');

  @override
  Future<void> selectCamera(String deviceId) async {}

  @override
  Future<void> stop() async {}

  @override
  bool get isActive => false;

  @override
  List<CameraDevice> get cameras => const [];

  @override
  String? get activeCameraId => null;

  @override
  String? get activeCameraLabel => null;

  @override
  int get frameWidth => 0;

  @override
  int get frameHeight => 0;

  @override
  Stream<FrameSourceEvent> get events => const Stream.empty();

  @override
  Widget preview() => const SizedBox.shrink();
}

FrameSource createFrameSource() => WebFrameSource();

/// Device facts for the session record (platform only outside the browser).
DeviceInfo currentDeviceInfo() =>
    DeviceInfo(platform: defaultTargetPlatform.name);

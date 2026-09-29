import 'dart:typed_data';

import '../api/api_exception.dart';
import '../models/gaze.dart';
import '../models/layout.dart';
import 'gaze_service_client.dart';

/// Scripted [GazeEstimator] for tests.
class FakeGazeEstimator implements GazeEstimator {
  FakeGazeEstimator({
    this.gazeInfo = const GazeInfo(
      modelId: 'fake-model',
      modelVersion: '0',
      synthetic: false,
      faceDetector: 'fake',
    ),
    this.faceConf = 0.9,
  });

  GazeInfo gazeInfo;
  double faceConf;

  /// When false, samples report no face.
  bool facePresent = true;

  /// When set, [estimate] throws it.
  ApiException? failure;

  int estimateCalls = 0;
  int infoCalls = 0;

  /// Overrides the generated sample.
  RawGazeSample Function(int tMs, int frameW, int frameH)? sampleBuilder;

  @override
  Future<GazeInfo> info() async {
    infoCalls++;
    if (failure != null) throw failure!;
    return gazeInfo;
  }

  @override
  Future<RawGazeSample> estimate(
    Uint8List jpegBytes,
    int tMs,
    int frameW,
    int frameH,
  ) async {
    estimateCalls++;
    if (failure != null) throw failure!;
    final builder = sampleBuilder;
    if (builder != null) return builder(tMs, frameW, frameH);
    if (!facePresent) {
      return RawGazeSample(
        tMs: tMs,
        faceDetected: false,
        frameW: frameW,
        frameH: frameH,
      );
    }
    return RawGazeSample(
      tMs: tMs,
      faceDetected: true,
      faceBox: const Box(200, 120, 240, 300),
      faceConf: faceConf,
      yawDeg: 1.5,
      pitchDeg: -2.0,
      gazeConf: 0.8,
      frameW: frameW,
      frameH: frameH,
    );
  }
}

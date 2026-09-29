import 'layout.dart';

/// What `GET /info` of the gaze service says about the estimator.
class GazeInfo {
  const GazeInfo({
    required this.modelId,
    required this.modelVersion,
    required this.synthetic,
    this.faceDetector = '',
    this.maxFps = 10,
  });

  final String modelId;
  final String modelVersion;

  /// True when the estimator is a development stub: sessions using it are
  /// flagged and never yield eye-region claims.
  final bool synthetic;
  final String faceDetector;
  final double maxFps;

  factory GazeInfo.fromJson(Map<String, dynamic> json) => GazeInfo(
        modelId: json['model_id']?.toString() ?? '',
        modelVersion: json['model_version']?.toString() ?? '',
        synthetic: json['synthetic'] == true,
        faceDetector: json['face_detector']?.toString() ?? '',
        maxFps: (json['max_fps'] as num?)?.toDouble() ?? 10,
      );

  Map<String, dynamic> toModelJson() => {
        'model_id': modelId,
        'model_version': modelVersion,
        'synthetic': synthetic,
      };
}

/// One raw gaze sample as the gaze service returns it. Never an image.
class RawGazeSample {
  const RawGazeSample({
    required this.tMs,
    required this.faceDetected,
    this.faceBox,
    this.faceConf = 0,
    this.yawDeg,
    this.pitchDeg,
    this.gazeConf = 0,
    this.frameW = 0,
    this.frameH = 0,
    this.modelId,
  });

  /// Client monotonic clock in milliseconds.
  final int tMs;
  final bool faceDetected;
  final Box? faceBox;
  final double faceConf;
  final double? yawDeg;
  final double? pitchDeg;
  final double gazeConf;
  final int frameW;
  final int frameH;

  /// Only present on the estimate response; never sent back to the server.
  final String? modelId;

  /// A sample the calibration can use: a face was found with its angles.
  bool get hasFace => faceDetected && yawDeg != null && pitchDeg != null;

  factory RawGazeSample.fromJson(
    Map<String, dynamic> json, {
    int fallbackTMs = 0,
  }) =>
      RawGazeSample(
        tMs: (json['t_ms'] as num?)?.toInt() ?? fallbackTMs,
        faceDetected: json['face_detected'] == true,
        faceBox: Box.maybeFromJson(json['face_box']),
        faceConf: (json['face_conf'] as num?)?.toDouble() ?? 0,
        yawDeg: (json['yaw_deg'] as num?)?.toDouble(),
        pitchDeg: (json['pitch_deg'] as num?)?.toDouble(),
        gazeConf: (json['gaze_conf'] as num?)?.toDouble() ?? 0,
        frameW: (json['frame_w'] as num?)?.toInt() ?? 0,
        frameH: (json['frame_h'] as num?)?.toInt() ?? 0,
        modelId: json['model_id']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        't_ms': tMs,
        'face_detected': faceDetected,
        'face_box': faceBox?.toJson(),
        'face_conf': faceConf,
        'yaw_deg': yawDeg,
        'pitch_deg': pitchDeg,
        'gaze_conf': gazeConf,
        'frame_w': frameW,
        'frame_h': frameH,
      };
}

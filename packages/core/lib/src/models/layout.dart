/// Screen size in CSS pixels plus the device pixel ratio.
class ScreenInfo {
  const ScreenInfo({required this.w, required this.h, this.dpr = 1});

  final double w;
  final double h;
  final double dpr;

  factory ScreenInfo.fromJson(Map<String, dynamic> json) => ScreenInfo(
        w: (json['w'] as num?)?.toDouble() ?? 0,
        h: (json['h'] as num?)?.toDouble() ?? 0,
        dpr: (json['dpr'] as num?)?.toDouble() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'w': w.round(),
        'h': h.round(),
        'dpr': dpr,
      };

  @override
  bool operator ==(Object other) =>
      other is ScreenInfo && other.w == w && other.h == h && other.dpr == dpr;

  @override
  int get hashCode => Object.hash(w, h, dpr);

  @override
  String toString() => '${w.round()} x ${h.round()} @${dpr}x';
}

/// Axis-aligned rectangle in CSS pixels. Wire form: `[x, y, w, h]`.
class Box {
  const Box(this.x, this.y, this.w, this.h);

  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get bottom => y + h;
  double get cx => x + w / 2;
  double get cy => y + h / 2;

  bool contains(double px, double py) =>
      px >= x && px <= right && py >= y && py <= bottom;

  /// True when [other] lies completely inside this box.
  bool containsBox(Box other) =>
      other.x >= x &&
      other.y >= y &&
      other.right <= right + 1e-6 &&
      other.bottom <= bottom + 1e-6;

  static Box? maybeFromJson(Object? value) {
    if (value is! List || value.length < 4) return null;
    final v = [for (final e in value.take(4)) (e as num).toDouble()];
    return Box(v[0], v[1], v[2], v[3]);
  }

  List<double> toJson() => [x, y, w, h];

  @override
  bool operator ==(Object other) =>
      other is Box &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'Box($x, $y, $w, $h)';
}

/// Stimulus geometry in CSS pixels of the participant's screen. The server
/// classifies gaze samples against these regions.
class StimulusLayout {
  const StimulusLayout({
    required this.screen,
    required this.faceBox,
    required this.eyeRegion,
    required this.mouthRegion,
  });

  final ScreenInfo screen;
  final Box faceBox;
  final Box eyeRegion;
  final Box mouthRegion;

  factory StimulusLayout.fromJson(Map<String, dynamic> json) => StimulusLayout(
        screen: ScreenInfo.fromJson(
          json['screen'] as Map<String, dynamic>? ?? const {},
        ),
        faceBox: Box.maybeFromJson(json['face_box']) ?? const Box(0, 0, 0, 0),
        eyeRegion:
            Box.maybeFromJson(json['eye_region']) ?? const Box(0, 0, 0, 0),
        mouthRegion:
            Box.maybeFromJson(json['mouth_region']) ?? const Box(0, 0, 0, 0),
      );

  Map<String, dynamic> toJson() => {
        'screen': screen.toJson(),
        'face_box': faceBox.toJson(),
        'eye_region': eyeRegion.toJson(),
        'mouth_region': mouthRegion.toJson(),
      };
}

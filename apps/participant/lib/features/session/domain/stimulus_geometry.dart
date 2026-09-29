import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';

/// Height of the control bar that overlays the top of the stimulus screens.
const double kControlBarHeight = 40;

/// Face card proportions (fractions of the face height). The eye region is the
/// upper half from the brow line to below the eyes, the mouth region the
/// lower half.
const double kEyeTop = 0.15;
const double kEyeBottom = 0.50;
const double kMouthTop = 0.55;
const double kMouthBottom = 0.95;

/// Width divided by height of the oval face card.
const double kFaceAspect = 0.72;

/// Smallest eye-region height the validation may use, in CSS pixels.
const double kMinEyeRegionHeight = 120;

/// Eye-region height must be at least this many times the calibration error.
const double kEyeHeightPerResidual = 3;

class TargetPoint {
  const TargetPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is TargetPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'TargetPoint($x, $y)';
}

/// Calibration targets for [count] points, inset 10 % from the screen edges.
/// Nine points form a 3 x 3 grid; five points are the corners and the centre;
/// other counts use the smallest grid that holds them, spread evenly.
List<TargetPoint> calibrationTargets(
  int count,
  ScreenInfo screen, {
  double inset = 0.10,
}) {
  double at(int i, int n, double size) => n <= 1
      ? size / 2
      : size * (inset + (1 - 2 * inset) * i / (n - 1));

  if (count == 5) {
    final l = at(0, 2, screen.w), r = at(1, 2, screen.w);
    final t = at(0, 2, screen.h), b = at(1, 2, screen.h);
    return [
      TargetPoint(l, t),
      TargetPoint(r, t),
      TargetPoint(screen.w / 2, screen.h / 2),
      TargetPoint(l, b),
      TargetPoint(r, b),
    ];
  }

  final cols = math.sqrt(count).ceil();
  final rows = (count / cols).ceil();
  final cells = [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++)
        TargetPoint(at(c, cols, screen.w), at(r, rows, screen.h)),
  ];
  if (cells.length == count) return cells;
  return [
    for (var i = 0; i < count; i++)
      cells[(i * (cells.length - 1) / (count - 1)).round()],
  ];
}

/// Space kept free left and right of the face card; the outside targets sit
/// in the middle of it.
double sideMargin(ScreenInfo screen) => math.max(56, screen.w * 0.08);

/// The face card layout for a screen and a calibration error.
class FaceLayout {
  const FaceLayout({
    required this.layout,
    required this.eyeHeight,
    required this.desiredEyeHeight,
  });

  final StimulusLayout layout;

  /// Eye-region height actually used, in CSS pixels.
  final double eyeHeight;

  /// max(120 px, 3 x calibration error): what the rule asks for.
  final double desiredEyeHeight;

  /// False when the screen is too small to reach [desiredEyeHeight]; the card
  /// then uses the largest size that fits and the server may fail the
  /// validation on its size ratio.
  bool get fits => eyeHeight + 1e-6 >= desiredEyeHeight;
}

/// Sizes the face card so the eye-region height is at least
/// max(120 px, 3 x [residualPx]) while the card fits the screen below the
/// control bar, centred.
FaceLayout buildFaceLayout({
  required ScreenInfo screen,
  required double residualPx,
  double topInset = kControlBarHeight,
  double bottomInset = 16,
}) {
  final side = sideMargin(screen);
  final top = topInset + 12;
  final availW = math.max(1.0, screen.w - 2 * side);
  final availH = math.max(1.0, screen.h - top - bottomInset);
  final maxFaceH = math.min(availH, availW / kFaceAspect);

  final desiredEye = math.max(
    kMinEyeRegionHeight,
    kEyeHeightPerResidual * residualPx,
  );
  final desiredFaceH = desiredEye / (kEyeBottom - kEyeTop);
  final faceH = math.min(desiredFaceH, maxFaceH);
  final faceW = faceH * kFaceAspect;
  final faceX = (screen.w - faceW) / 2;
  final faceY = top + (availH - faceH) / 2;

  final face = Box(faceX, faceY, faceW, faceH);
  final eye = Box(
    faceX + 0.10 * faceW,
    faceY + kEyeTop * faceH,
    0.80 * faceW,
    (kEyeBottom - kEyeTop) * faceH,
  );
  final mouth = Box(
    faceX + 0.20 * faceW,
    faceY + kMouthTop * faceH,
    0.60 * faceW,
    (kMouthBottom - kMouthTop) * faceH,
  );
  return FaceLayout(
    layout: StimulusLayout(
      screen: screen,
      faceBox: face,
      eyeRegion: eye,
      mouthRegion: mouth,
    ),
    eyeHeight: eye.h,
    desiredEyeHeight: desiredEye,
  );
}

/// One dot of the regional validation.
class ValidationTargetSpec {
  const ValidationTargetSpec({
    required this.label,
    required this.region,
    required this.x,
    required this.y,
  });

  /// Human readable name, e.g. `Left eye`.
  final String label;

  /// `eye`, `mouth` or `outside` as the server expects.
  final String region;
  final double x;
  final double y;
}

/// The seven validation dots in order: eye-left, eye-right, eye-centre,
/// mouth-left, mouth-right, then the outside corners top-left and
/// bottom-right.
List<ValidationTargetSpec> validationTargets(
  StimulusLayout layout, {
  double topInset = kControlBarHeight,
}) {
  final f = layout.faceBox;
  final s = layout.screen;
  final eyeY = f.y + (kEyeTop + kEyeBottom) / 2 * f.h;
  final mouthY = f.y + (kMouthTop + kMouthBottom) / 2 * f.h;
  final corner = sideMargin(s) / 2;
  return [
    ValidationTargetSpec(
        label: 'Left eye', region: 'eye', x: f.x + 0.30 * f.w, y: eyeY),
    ValidationTargetSpec(
        label: 'Right eye', region: 'eye', x: f.x + 0.70 * f.w, y: eyeY),
    ValidationTargetSpec(
        label: 'Between the eyes', region: 'eye', x: f.cx, y: eyeY),
    ValidationTargetSpec(
        label: 'Left of mouth',
        region: 'mouth',
        x: f.x + 0.36 * f.w,
        y: mouthY),
    ValidationTargetSpec(
        label: 'Right of mouth',
        region: 'mouth',
        x: f.x + 0.64 * f.w,
        y: mouthY),
    ValidationTargetSpec(
        label: 'Top-left corner',
        region: 'outside',
        x: corner,
        y: topInset + 36),
    ValidationTargetSpec(
        label: 'Bottom-right corner',
        region: 'outside',
        x: s.w - corner,
        y: s.h - 28),
  ];
}

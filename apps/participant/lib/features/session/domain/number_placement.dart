import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';

import 'stimulus_geometry.dart';

/// Where a number (or symbol) is drawn: its bounding rectangle in CSS pixels
/// of the screen. The centre is what the server stores as the position.
class NumberPlacement {
  const NumberPlacement({required this.zone, required this.rect});

  final NumberZone zone;
  final Box rect;

  double get x => rect.cx;
  double get y => rect.cy;
}

/// Space reserved at the bottom of the screen for the response controls, so
/// the face card (and the numbers) never sit under them.
double practiceBarReserve(ScreenInfo screen) =>
    (screen.h * 0.24).clamp(96.0, 168.0);

/// Font size of the number for a face card: it grows with the card.
double numberFontSize(Box face) => (face.h * 0.075).clamp(18.0, 44.0);

/// Size of the box that holds [chars] characters at [fontSize].
({double w, double h}) numberBoxSize(double fontSize, int chars) => (
      w: fontSize * 0.62 * chars + 12,
      h: fontSize * 1.3,
    );

bool _overlap(Box a, Box b) =>
    a.x < b.right && a.right > b.x && a.y < b.bottom && a.bottom > b.y;

/// Chooses where the number of a trial appears, relative to the face card:
///
/// * `outside`: beside, above or below the card, on a random side, never on it;
/// * `face_edge`: just inside the card's edge, on the forehead or a cheek;
/// * `near_eyes`: directly below the eye region or beside it, never over it;
/// * `eye_region`: inside the eye region (upper half of the face), between
///   or around the eyes.
///
/// [chars] is the number of digits (a symbol counts as two). [topInset] and
/// [bottomInset] keep the number clear of the control bar and the response
/// controls. The result always lies on the screen.
NumberPlacement placeNumber({
  required NumberZone zone,
  required StimulusLayout layout,
  required int chars,
  required math.Random random,
  double topInset = kControlBarHeight,
  double bottomInset = 0,
}) {
  final f = layout.faceBox;
  final eye = layout.eyeRegion;
  final screen = layout.screen;
  final size = numberBoxSize(numberFontSize(f), chars);
  final nw = size.w, nh = size.h;
  const edge = 4.0;
  final minX = edge, maxX = screen.w - edge;
  final minY = topInset + edge, maxY = screen.h - bottomInset - edge;

  Box at(double cx, double cy) => Box(cx - nw / 2, cy - nh / 2, nw, nh);
  double between(double lo, double hi) =>
      hi <= lo ? (lo + hi) / 2 : lo + random.nextDouble() * (hi - lo);
  bool onScreen(Box r) =>
      r.x >= minX - 1e-6 &&
      r.right <= maxX + 1e-6 &&
      r.y >= minY - 1e-6 &&
      r.bottom <= maxY + 1e-6;
  bool insideOval(Box r, double k) {
    final rx = f.w / 2 * k, ry = f.h / 2 * k;
    for (final p in [
      (r.x, r.y),
      (r.right, r.y),
      (r.x, r.bottom),
      (r.right, r.bottom),
    ]) {
      final dx = (p.$1 - f.cx) / rx, dy = (p.$2 - f.cy) / ry;
      if (dx * dx + dy * dy > 1) return false;
    }
    return true;
  }

  NumberPlacement done(Box r) => NumberPlacement(zone: zone, rect: r);

  switch (zone) {
    case NumberZone.outside:
      const gap = 10.0;
      final options = <Box Function()>[
        if (f.x - gap - nw >= minX)
          () => at(between(minX + nw / 2, f.x - gap - nw / 2),
              between(minY + nh / 2, maxY - nh / 2)),
        if (f.right + gap + nw <= maxX)
          () => at(between(f.right + gap + nw / 2, maxX - nw / 2),
              between(minY + nh / 2, maxY - nh / 2)),
        if (f.y - gap - nh >= minY)
          () => at(between(minX + nw / 2, maxX - nw / 2),
              between(minY + nh / 2, f.y - gap - nh / 2)),
        if (f.bottom + gap + nh <= maxY)
          () => at(between(minX + nw / 2, maxX - nw / 2),
              between(f.bottom + gap + nh / 2, maxY - nh / 2)),
      ];
      if (options.isNotEmpty) {
        return done(options[random.nextInt(options.length)]());
      }
      // No room on any side: the corner of the usable area farthest from
      // the card's centre.
      final corners = [
        at(minX + nw / 2, minY + nh / 2),
        at(maxX - nw / 2, minY + nh / 2),
        at(minX + nw / 2, maxY - nh / 2),
        at(maxX - nw / 2, maxY - nh / 2),
      ];
      corners.sort((a, b) {
        double d(Box r) =>
            math.pow(r.cx - f.cx, 2).toDouble() +
            math.pow(r.cy - f.cy, 2).toDouble();
        return d(b).compareTo(d(a));
      });
      return done(corners.first);

    case NumberZone.faceEdge:
      // Forehead: the strip between the top of the card and the eye region.
      Box? forehead() {
        final top = f.y + 0.035 * f.h + nh / 2;
        final bottom = eye.y - 2 - nh / 2;
        if (bottom < top) return null;
        for (var i = 0; i < 30; i++) {
          final r = at(f.cx + between(-0.12, 0.12) * f.w, between(top, bottom));
          if (insideOval(r, 0.985) && !_overlap(r, eye)) return r;
        }
        return null;
      }

      // Cheek: the outer edge of the box touches a slightly shrunken oval.
      Box? cheek(bool left) {
        for (var i = 0; i < 30; i++) {
          final cy = f.y + between(0.58, 0.78) * f.h;
          double halfWidth(double y) {
            final t = ((y - f.cy) / (f.h / 2)).clamp(-1.0, 1.0);
            return f.w / 2 * 0.97 * math.sqrt(1 - t * t);
          }

          final hw = math.min(halfWidth(cy - nh / 2), halfWidth(cy + nh / 2));
          if (hw < nw) continue;
          final cx = left ? f.cx - (hw - nw / 2) : f.cx + (hw - nw / 2);
          final r = at(cx, cy);
          if (insideOval(r, 0.985)) return r;
        }
        return null;
      }

      final options = <Box? Function()>[forehead, () => cheek(true), () => cheek(false)]
        ..shuffle(random);
      for (final option in options) {
        final r = option();
        if (r != null && onScreen(r)) return done(r);
      }
      return done(at(f.cx, f.y + 0.035 * f.h + nh / 2 + 1));

    case NumberZone.nearEyes:
      const gap = 3.0;
      final options = <Box Function()>[
        // Beside the eyes: just outside the side of the card at eye height.
        if (f.x - gap - nw >= minX)
          () => at(f.x - gap - nw / 2, between(eye.y + nh / 2, eye.bottom - nh / 2)),
        if (f.right + gap + nw <= maxX)
          () => at(f.right + gap + nw / 2, between(eye.y + nh / 2, eye.bottom - nh / 2)),
        // Below the eyes: on the nose and the cheeks under the eye region.
        () => at(between(f.x + 0.18 * f.w + nw / 2, f.right - 0.18 * f.w - nw / 2),
            eye.bottom + gap + nh / 2),
      ];
      for (var i = 0; i < 20; i++) {
        final r = options[random.nextInt(options.length)]();
        if (!_overlap(r, eye) && onScreen(r)) return done(r);
      }
      return done(at(f.cx, eye.bottom + gap + nh / 2));

    case NumberZone.eyeRegion:
      // The eyes themselves stay clear.
      final eyeY = f.y + 0.325 * f.h;
      final keepOut = [
        for (final dx in const [0.30, 0.70])
          Box(f.x + (dx - 0.10) * f.w, eyeY - 0.05 * f.h, 0.20 * f.w, 0.10 * f.h),
      ];
      for (var i = 0; i < 60; i++) {
        final r = at(between(eye.x + nw / 2, eye.right - nw / 2),
            between(eye.y + nh / 2, eye.bottom - nh / 2));
        if (eye.containsBox(r) && !keepOut.any((k) => _overlap(r, k))) {
          return done(r);
        }
      }
      return done(at(f.cx, eye.cy));
  }
}

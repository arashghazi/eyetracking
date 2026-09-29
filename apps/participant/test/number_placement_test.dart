import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/domain/number_placement.dart';
import 'package:participant_app/features/session/domain/stimulus_geometry.dart';

bool overlaps(Box a, Box b) =>
    a.x < b.right && a.right > b.x && a.y < b.bottom && a.bottom > b.y;

bool insideOval(Box r, Box f) {
  final rx = f.w / 2, ry = f.h / 2;
  for (final p in [(r.x, r.y), (r.right, r.y), (r.x, r.bottom), (r.right, r.bottom)]) {
    final dx = (p.$1 - f.cx) / rx, dy = (p.$2 - f.cy) / ry;
    if (dx * dx + dy * dy > 1) return false;
  }
  return true;
}

/// Gap between two boxes (0 when they touch or overlap).
double gap(Box a, Box b) {
  final dx = math.max(0.0, math.max(a.x - b.right, b.x - a.right));
  final dy = math.max(0.0, math.max(a.y - b.bottom, b.y - a.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

void main() {
  const screens = [
    ScreenInfo(w: 360, h: 640),
    ScreenInfo(w: 800, h: 900),
    ScreenInfo(w: 1440, h: 900),
  ];

  for (final screen in screens) {
    group('placement on ${screen.w.toInt()} x ${screen.h.toInt()}', () {
      final reserve = practiceBarReserve(screen);
      final layout = buildFaceLayout(
        screen: screen,
        residualPx: 60,
        bottomInset: reserve,
      ).layout;
      final face = layout.faceBox;
      final eye = layout.eyeRegion;

      /// Runs [check] for many random placements of one zone.
      void forEachPlacement(
        NumberZone zone,
        void Function(Box rect, int seed, int chars) check,
      ) {
        for (var seed = 0; seed < 150; seed++) {
          for (final chars in [1, 2]) {
            final p = placeNumber(
              zone: zone,
              layout: layout,
              chars: chars,
              random: math.Random(seed),
              bottomInset: reserve,
            );
            expect(p.zone, zone);
            // Always on the screen, below the control bar, above the answer
            // controls.
            expect(p.rect.x, greaterThanOrEqualTo(0), reason: 'seed $seed');
            expect(p.rect.right, lessThanOrEqualTo(screen.w), reason: 'seed $seed');
            expect(p.rect.y, greaterThanOrEqualTo(kControlBarHeight),
                reason: 'seed $seed');
            expect(p.rect.bottom, lessThanOrEqualTo(screen.h - reserve),
                reason: 'seed $seed');
            check(p.rect, seed, chars);
          }
        }
      }

      test('outside is outside the face card, on both sides over many trials', () {
        final sides = <String>{};
        forEachPlacement(NumberZone.outside, (r, seed, chars) {
          expect(overlaps(r, face), isFalse, reason: 'seed $seed: $r vs $face');
          sides.add(r.cx < face.cx ? 'left' : 'right');
        });
        expect(sides, containsAll(['left', 'right']));
      });

      test('face_edge is just inside the face edge', () {
        forEachPlacement(NumberZone.faceEdge, (r, seed, chars) {
          expect(face.containsBox(r), isTrue, reason: 'seed $seed');
          expect(insideOval(r, face), isTrue, reason: 'seed $seed');
          expect(eye.contains(r.cx, r.cy), isFalse, reason: 'seed $seed');
          // Near the edge: some corner is close to the oval boundary.
          final rx = face.w / 2, ry = face.h / 2;
          var maxRadius = 0.0;
          for (final p in [(r.x, r.y), (r.right, r.y), (r.x, r.bottom), (r.right, r.bottom)]) {
            final dx = (p.$1 - face.cx) / rx, dy = (p.$2 - face.cy) / ry;
            maxRadius = math.max(maxRadius, math.sqrt(dx * dx + dy * dy));
          }
          expect(maxRadius, greaterThan(0.75), reason: 'seed $seed is not at the edge');
        });
      });

      test('near_eyes never overlaps the eye region and stays close to it', () {
        forEachPlacement(NumberZone.nearEyes, (r, seed, chars) {
          expect(overlaps(r, eye), isFalse, reason: 'seed $seed: $r vs $eye');
          expect(gap(r, eye), lessThan(0.2 * face.h), reason: 'seed $seed');
        });
      });

      test('eye_region is inside the upper half of the face', () {
        forEachPlacement(NumberZone.eyeRegion, (r, seed, chars) {
          expect(eye.containsBox(r), isTrue, reason: 'seed $seed');
          expect(face.containsBox(r), isTrue, reason: 'seed $seed');
          expect(r.bottom, lessThanOrEqualTo(face.cy), reason: 'seed $seed');
        });
      });
    });
  }

  test('the zones differ: the closer the zone, the closer to the eyes', () {
    const screen = ScreenInfo(w: 1440, h: 900);
    final layout = buildFaceLayout(
      screen: screen,
      residualPx: 60,
      bottomInset: practiceBarReserve(screen),
    ).layout;
    double meanDistance(NumberZone zone) {
      var total = 0.0;
      for (var seed = 0; seed < 100; seed++) {
        final p = placeNumber(
          zone: zone,
          layout: layout,
          chars: 2,
          random: math.Random(seed),
          bottomInset: practiceBarReserve(screen),
        );
        total += gap(p.rect, layout.eyeRegion);
      }
      return total / 100;
    }

    expect(meanDistance(NumberZone.outside),
        greaterThan(meanDistance(NumberZone.faceEdge)));
    expect(meanDistance(NumberZone.nearEyes),
        lessThan(meanDistance(NumberZone.faceEdge)));
    expect(meanDistance(NumberZone.eyeRegion), 0);
  });

  test('the answer controls get 96 to 168 px and the number grows with the face', () {
    expect(practiceBarReserve(const ScreenInfo(w: 300, h: 300)), 96);
    expect(practiceBarReserve(const ScreenInfo(w: 1440, h: 900)), 168);
    expect(numberFontSize(const Box(0, 0, 100, 100)), 18);
    expect(numberFontSize(const Box(0, 0, 300, 400)), 30);
    expect(numberFontSize(const Box(0, 0, 900, 1200)), 44);
  });
}

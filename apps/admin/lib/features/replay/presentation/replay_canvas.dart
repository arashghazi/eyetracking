import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// Where the participant's screen sits inside the drawing area: scaled to
/// fit, centred, aspect ratio kept.
class ScreenFit {
  const ScreenFit({required this.scale, required this.origin, required this.rect});

  final double scale;

  /// Canvas position of the screen's top-left corner.
  final Offset origin;

  /// The screen rectangle on the canvas.
  final Rect rect;

  static ScreenFit of(Size canvas, ScreenInfo screen, {double padding = 8}) {
    final w = screen.w <= 0 ? 1280.0 : screen.w;
    final h = screen.h <= 0 ? 720.0 : screen.h;
    final availableW = math.max(1.0, canvas.width - 2 * padding);
    final availableH = math.max(1.0, canvas.height - 2 * padding);
    final scale = math.min(availableW / w, availableH / h);
    final size = Size(w * scale, h * scale);
    final origin = Offset(
      (canvas.width - size.width) / 2,
      (canvas.height - size.height) / 2,
    );
    return ScreenFit(scale: scale, origin: origin, rect: origin & size);
  }

  /// Canvas point of the screen point ([x], [y]) in CSS pixels.
  Offset point(double x, double y) =>
      Offset(origin.dx + x * scale, origin.dy + y * scale);

  Rect box(Box b) =>
      Rect.fromLTWH(origin.dx + b.x * scale, origin.dy + b.y * scale, b.w * scale, b.h * scale);
}

/// Draws the participant's screen and what was on it: the layout regions,
/// the trial number, the gaze estimate with its fading trail. Display only:
/// no smoothing, no interpolation, and a sample without x and y draws
/// nothing.
class ReplayCanvasPainter extends CustomPainter {
  ReplayCanvasPainter({
    required this.screen,
    required this.positionMs,
    this.layout,
    this.sample,
    this.trail = const [],
    this.trial,
    this.trailMs = 500,
  });

  final ScreenInfo screen;
  final int positionMs;
  final StimulusLayout? layout;
  final ReplaySample? sample;

  /// Samples with a position from the last [trailMs], oldest first.
  final List<ReplaySample> trail;
  final ReplayTrial? trial;
  final int trailMs;

  static const _faceColor = Color(0xFF566666);
  static const _eyeColor = Color(0xFF185ABC);
  static const _mouthColor = Color(0xFF8A5A00);
  static const _gazeColor = Color(0xFFA83232);

  @override
  void paint(Canvas canvas, Size size) {
    final fit = ScreenFit.of(size, screen);

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE9EDED));
    canvas.drawRect(fit.rect, Paint()..color = Colors.white);

    // Everything on the screen is clipped to the screen rectangle; the gaze
    // may leave it, so it is drawn after the clip is released.
    canvas.save();
    canvas.clipRect(fit.rect);
    final l = layout;
    if (l != null) {
      _region(canvas, fit, l.faceBox, _faceColor, 'Face', fill: 0.05);
      _region(canvas, fit, l.eyeRegion, _eyeColor, 'Eye region', fill: 0.16);
      _region(canvas, fit, l.mouthRegion, _mouthColor, 'Mouth region', fill: 0.16);
    }
    final t = trial;
    if (t != null && t.hasPosition) _trialNumber(canvas, fit, t);
    canvas.restore();

    canvas.drawRect(
      fit.rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF8C9A9A),
    );

    _gaze(canvas, fit);
  }

  void _region(
    Canvas canvas,
    ScreenFit fit,
    Box box,
    Color color,
    String label, {
    required double fill,
  }) {
    if (box.w <= 0 || box.h <= 0) return;
    final rect = fit.box(box);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: fill));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(20, rect.width - 6));
    text.paint(canvas, rect.topLeft + const Offset(3, 2));
  }

  void _trialNumber(Canvas canvas, ScreenFit fit, ReplayTrial trial) {
    final centre = fit.point(trial.x!, trial.y!);
    final text = TextPainter(
      text: TextSpan(
        text: trial.numberShown,
        style: TextStyle(
          color: const Color(0xFF1E2B2B),
          fontSize: math.max(14, 44 * fit.scale),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = centre - Offset(text.width / 2, text.height / 2);
    canvas.drawRect(
      (at & text.size).inflate(3),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    text.paint(canvas, at);
  }

  void _gaze(Canvas canvas, ScreenFit fit) {
    final current = sample;
    // The trail: older samples fainter and smaller. Nothing is interpolated
    // and nothing is smoothed; each dot is one estimate.
    for (final s in trail) {
      if (!s.hasPosition) continue;
      if (current != null && s.tMs == current.tMs) continue;
      final age = (positionMs - s.tMs).clamp(0, trailMs) / trailMs;
      final alpha = (1 - age) * 0.5;
      if (alpha <= 0.01) continue;
      canvas.drawCircle(
        fit.point(s.x!, s.y!),
        3 + 2 * (1 - age),
        Paint()..color = _gazeColor.withValues(alpha: alpha),
      );
    }
    if (current != null && current.hasPosition) {
      final p = fit.point(current.x!, current.y!);
      canvas.drawCircle(p, 8, Paint()..color = _gazeColor.withValues(alpha: 0.9));
      canvas.drawCircle(
        p,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(ReplayCanvasPainter old) =>
      old.screen != screen ||
      old.positionMs != positionMs ||
      old.layout != layout ||
      old.sample != sample ||
      old.trial != trial ||
      old.trail.length != trail.length;
}

import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// Colours of the segment bands (the label is written on each band too, so
/// colour is never the only cue).
Color segmentColor(String label) => switch (label) {
      'baseline' => const Color(0xFF185ABC),
      'practice' => const Color(0xFF2B7A4B),
      'post' => const Color(0xFF7A4F9A),
      _ => const Color(0xFF566666),
    };

/// Vertical layout of the timeline, shared by the painter and the tests.
abstract final class TimelineMetrics {
  static const bandTop = 0.0;
  static const bandHeight = 24.0;
  static const stripTop = 30.0;
  static const stripHeight = 22.0;
  static const height = 58.0;
}

/// The scrubber: segment bands, gap and pause shading, the quality strip
/// (valid share per second, one thin bar each) and the playhead.
class ReplayTimelinePainter extends CustomPainter {
  ReplayTimelinePainter({required this.bundle, required this.positionMs});

  final ReplayBundle bundle;
  final int positionMs;

  double _x(int ms, double width) {
    final d = bundle.durationMs;
    return d <= 0 ? 0 : (ms / d).clamp(0.0, 1.0) * width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const bandTop = TimelineMetrics.bandTop;
    const bandH = TimelineMetrics.bandHeight;
    const stripTop = TimelineMetrics.stripTop;
    const stripH = TimelineMetrics.stripHeight;
    final w = size.width;

    // Track.
    canvas.drawRect(
      Rect.fromLTWH(0, bandTop, w, bandH),
      Paint()..color = const Color(0xFFE9EDED),
    );

    // Segment bands with their names.
    for (final s in bundle.segments) {
      final end = s.endedMs ?? bundle.durationMs;
      final rect = Rect.fromLTRB(_x(s.startedMs, w), bandTop, _x(end, w), bandTop + bandH);
      if (rect.width <= 0) continue;
      final color = segmentColor(s.label);
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.22));
      canvas.drawRect(
        Rect.fromLTWH(rect.left, bandTop, rect.width, 3),
        Paint()..color = color,
      );
      final text = TextPainter(
        text: TextSpan(
          text: s.label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, rect.width - 6));
      if (rect.width > 24) text.paint(canvas, Offset(rect.left + 4, bandTop + 6));
    }

    // Gaps (no samples): grey hatching over both rows.
    for (final g in bundle.gaps) {
      final rect = Rect.fromLTRB(
          _x(g.fromMs, w), bandTop, math.max(_x(g.toMs, w), _x(g.fromMs, w) + 1),
          stripTop + stripH);
      canvas.drawRect(rect, Paint()..color = const Color(0xFF566666).withValues(alpha: 0.18));
      _hatch(canvas, rect, const Color(0xFF566666));
    }

    // Pauses: amber shading.
    for (final p in bundle.pauses) {
      final rect = Rect.fromLTRB(
          _x(p.fromMs, w), bandTop, math.max(_x(p.toMs, w), _x(p.fromMs, w) + 1),
          stripTop + stripH);
      canvas.drawRect(rect, Paint()..color = const Color(0xFFE0A100).withValues(alpha: 0.28));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF8A5A00).withValues(alpha: 0.6),
      );
    }

    // Quality strip: valid share per second. A second without samples
    // (share unknown) is an empty outlined slot, not a zero.
    canvas.drawRect(
      Rect.fromLTWH(0, stripTop, w, stripH),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFD3DADA),
    );
    for (final q in bundle.qualityStrip) {
      final left = _x(q.fromMs, w);
      final right = math.max(_x(q.toMs, w), left + 1);
      final share = q.validShare;
      if (share == null) {
        canvas.drawRect(
          Rect.fromLTRB(left + 0.5, stripTop + stripH - 3, right - 0.5, stripTop + stripH),
          Paint()..color = const Color(0xFF8C9A9A),
        );
        continue;
      }
      final h = math.max(1.0, share.clamp(0.0, 1.0) * (stripH - 2));
      canvas.drawRect(
        Rect.fromLTRB(left, stripTop + stripH - 1 - h, math.max(left + 0.5, right - 0.5), stripTop + stripH - 1),
        Paint()..color = Color.lerp(const Color(0xFFA83232), const Color(0xFF2B7A4B), share.clamp(0.0, 1.0))!,
      );
    }

    // Playhead.
    final x = _x(positionMs, w);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, TimelineMetrics.height),
      Paint()
        ..color = const Color(0xFF1E2B2B)
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(x, TimelineMetrics.height - 3), 5, Paint()..color = const Color(0xFF1E2B2B));
  }

  void _hatch(Canvas canvas, Rect rect, Color color) {
    canvas.save();
    canvas.clipRect(rect);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var x = rect.left - rect.height; x < rect.right; x += 6) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ReplayTimelinePainter old) =>
      old.bundle != bundle || old.positionMs != positionMs;
}

/// The scrubber widget: tap or drag to move, or use the slider semantics.
class ReplayTimeline extends StatelessWidget {
  const ReplayTimeline({
    super.key,
    required this.bundle,
    required this.positionMs,
    required this.onSeek,
  });

  final ReplayBundle bundle;
  final int positionMs;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      void seekAt(double dx) {
        if (width <= 0) return;
        onSeek((dx / width * bundle.durationMs).round());
      }

      return Semantics(
        // Its own node: without it the slider is merged into the text
        // around it and screen readers cannot find it.
        container: true,
        slider: true,
        label: 'Replay position',
        value: formatClockMs(positionMs),
        increasedValue: formatClockMs(math.min(bundle.durationMs, positionMs + 100)),
        decreasedValue: formatClockMs(math.max(0, positionMs - 100)),
        onIncrease: () => onSeek(positionMs + 100),
        onDecrease: () => onSeek(positionMs - 100),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragStart: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              key: const Key('replay-scrubber'),
              width: width,
              height: TimelineMetrics.height,
              child: CustomPaint(
                painter: ReplayTimelinePainter(bundle: bundle, positionMs: positionMs),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// What the colours and marks of the timeline mean.
class ReplayTimelineLegend extends StatelessWidget {
  const ReplayTimelineLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    Widget item(Color color, String text, {bool outlined = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: outlined ? Colors.transparent : color.withValues(alpha: 0.5),
                border: Border.all(color: color),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: style)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        item(segmentColor('baseline'), 'Baseline'),
        item(segmentColor('practice'), 'Practice'),
        item(segmentColor('post'), 'Post'),
        item(const Color(0xFF566666), 'Gap (no samples)'),
        item(const Color(0xFFE0A100), 'Pause'),
        item(const Color(0xFF2B7A4B), 'Valid share per second (lower strip)'),
      ],
    );
  }
}


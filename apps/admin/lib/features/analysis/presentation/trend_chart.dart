import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// One bar of the trend chart: the baseline or the post eye share of one
/// session. A bar with no value (not evaluable) is [hollow]: an outlined
/// stub, never a zero.
class TrendBar {
  const TrendBar({
    required this.rect,
    required this.hollow,
    required this.post,
    required this.pointIndex,
    this.share,
  });

  final Rect rect;
  final bool hollow;

  /// False for the baseline bar, true for the post bar.
  final bool post;
  final int pointIndex;
  final double? share;
}

/// The comfort mean of one session, drawn as a small diamond.
class TrendMarker {
  const TrendMarker({required this.center, required this.pointIndex, required this.value});

  final Offset center;
  final int pointIndex;
  final double value;
}

/// Where everything of a trend chart goes, computed from the size alone so
/// the painter and the tests agree.
class TrendGeometry {
  const TrendGeometry({
    required this.plot,
    required this.slots,
    required this.bars,
    required this.markers,
  });

  /// The area of the 0..1 scale.
  final Rect plot;

  /// One slot per session, oldest first.
  final List<Rect> slots;
  final List<TrendBar> bars;
  final List<TrendMarker> markers;

  /// Height of the outlined stub that stands for "no value", as a share of
  /// the scale.
  static const hollowShare = 0.12;

  /// The comfort scale the marker uses (1..5); the marker's height is
  /// `mean / scaleMax`.
  static const comfortScaleMax = 5.0;

  static const _left = 38.0;
  static const _right = 22.0;
  static const _top = 8.0;
  static const _bottom = 24.0;

  static TrendGeometry of(Size size, List<TrendPoint> points) {
    final plot = Rect.fromLTRB(
      _left,
      _top,
      math.max(_left + 1, size.width - _right),
      math.max(_top + 1, size.height - _bottom),
    );
    final n = points.length;
    final slotW = n == 0 ? plot.width : plot.width / n;
    final barW = math.min(18.0, math.max(3.0, slotW * 0.28));
    final slots = <Rect>[];
    final bars = <TrendBar>[];
    final markers = <TrendMarker>[];
    for (var i = 0; i < n; i++) {
      final slot = Rect.fromLTWH(plot.left + i * slotW, plot.top, slotW, plot.height);
      slots.add(slot);
      final p = points[i];
      final cx = slot.center.dx;
      for (final post in [false, true]) {
        final share = post ? p.postEyeShare : p.baselineEyeShare;
        final hollow = share == null;
        final h = share == null
            ? plot.height * hollowShare
            : math.max(share.clamp(0.0, 1.0) * plot.height, share > 0 ? 1.0 : 0.0);
        final left = post ? cx + 1 : cx - 1 - barW;
        bars.add(TrendBar(
          rect: Rect.fromLTWH(left, plot.bottom - h, barW, h),
          hollow: hollow,
          post: post,
          pointIndex: i,
          share: share,
        ));
      }
      final comfort = p.comfortMean;
      if (comfort != null) {
        final y = plot.bottom - (comfort / comfortScaleMax).clamp(0.0, 1.0) * plot.height;
        markers.add(TrendMarker(center: Offset(cx, y), pointIndex: i, value: comfort));
      }
    }
    return TrendGeometry(plot: plot, slots: slots, bars: bars, markers: markers);
  }
}

/// Paints the trend of one participant within one comparable group: a pair
/// of bars per session (baseline eye share, post eye share, both on 0..1)
/// with the comfort mean as a small marker, sessions in date order.
class TrendChartPainter extends CustomPainter {
  TrendChartPainter({
    required this.points,
    this.baselineColor = const Color(0xFF7FA6D9),
    this.postColor = const Color(0xFF185ABC),
    this.markerColor = const Color(0xFF8A5A00),
    this.axisColor = const Color(0xFF8C9A9A),
    this.textColor = const Color(0xFF566666),
  });

  final List<TrendPoint> points;
  final Color baselineColor;
  final Color postColor;
  final Color markerColor;
  final Color axisColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final g = TrendGeometry.of(size, points);
    final plot = g.plot;

    // Grid and the two axes.
    final grid = Paint()
      ..color = axisColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (final v in [0.0, 0.5, 1.0]) {
      final y = plot.bottom - v * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, '${(v * 100).round()} %', Offset(plot.left - 6, y), alignRight: true);
    }
    for (var c = 1; c <= TrendGeometry.comfortScaleMax; c++) {
      final y = plot.bottom - c / TrendGeometry.comfortScaleMax * plot.height;
      _text(canvas, '$c', Offset(plot.right + 4, y), size: 9, color: markerColor);
    }

    // Bars: a value is a filled bar, "no value" an outlined stub.
    for (final bar in g.bars) {
      final color = bar.post ? postColor : baselineColor;
      if (bar.hollow) {
        canvas.drawRect(
          bar.rect.deflate(0.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color,
        );
      } else {
        canvas.drawRect(bar.rect, Paint()..style = PaintingStyle.fill..color = color);
      }
    }

    // Comfort markers.
    for (final m in g.markers) {
      final path = Path()
        ..moveTo(m.center.dx, m.center.dy - 5)
        ..lineTo(m.center.dx + 5, m.center.dy)
        ..lineTo(m.center.dx, m.center.dy + 5)
        ..lineTo(m.center.dx - 5, m.center.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = markerColor);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white,
      );
    }

    // Baseline axis and date labels (thinned out when crowded).
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1.5,
    );
    final every = math.max(1, (points.length / math.max(1, plot.width / 44)).ceil());
    for (var i = 0; i < points.length; i += every) {
      _text(
        canvas,
        _dateLabel(points[i].createdAt, i),
        Offset(g.slots[i].center.dx, plot.bottom + 4),
        center: true,
        below: true,
      );
    }
  }

  static String _dateLabel(String? iso, int index) {
    final parsed = iso == null ? null : DateTime.tryParse(iso);
    if (parsed == null) return '#${index + 1}';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.month)}-${two(parsed.day)}';
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    bool alignRight = false,
    bool center = false,
    bool below = false,
    double size = 10,
    Color? color,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color ?? textColor)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    final dy = below ? at.dy : at.dy - tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(TrendChartPainter old) => old.points != points;
}

/// A trend card: one participant within one comparable group.
class TrendCard extends StatelessWidget {
  const TrendCard({super.key, required this.trend, this.group});

  final AnalysisTrend trend;
  final AnalysisGroup? group;

  /// A readable line for a group: platform, protocol version, estimator and
  /// the size bucket; the raw key when the group is unknown.
  static String groupText(AnalysisGroup? g, String fallbackKey) {
    if (g == null) return fallbackKey;
    final parts = [
      if (g.devicePlatform != null) g.devicePlatform!,
      if (g.protocolVersion != null) 'protocol v${g.protocolVersion}',
      if (g.estimator != null) g.estimator!,
      if (g.screenBucket != null) g.screenBucket!,
      if (g.stimulusBucket != null) 'stimulus ${_bucketText(g.stimulusBucket!)}',
    ];
    return parts.isEmpty ? fallbackKey : parts.join(' · ');
  }

  /// `150px` stays, a bare `150` gets its unit.
  static String _bucketText(String bucket) =>
      RegExp(r'^\d+$').hasMatch(bucket) ? '$bucket px' : bucket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = trend.points;
    final notEvaluable = points.where((p) => !p.evaluable).length;
    return Card(
      key: Key('trend-${trend.participantCode}-${trend.groupKey}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trend.participantCode,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: kMonospaceFallback,
              ),
            ),
            Text(
              groupText(group, trend.groupKey),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Eye share of ${points.length} sessions of ${trend.participantCode}',
              child: SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  key: Key('trend-chart-${trend.participantCode}-${trend.groupKey}'),
                  painter: TrendChartPainter(points: points),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${points.length} session${points.length == 1 ? '' : 's'}'
              '${notEvaluable > 0 ? ' · $notEvaluable not evaluable (hollow)' : ''}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            const _TrendLegend(),
          ],
        ),
      ),
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    Widget swatch(Color color, String text, {bool hollow = false, bool diamond = false}) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: diamond ? math.pi / 4 : 0,
              child: Container(
                width: diamond ? 9 : 12,
                height: diamond ? 9 : 12,
                decoration: BoxDecoration(
                  color: hollow ? Colors.transparent : color,
                  border: hollow ? Border.all(color: color, width: 1.5) : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: style)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        swatch(const Color(0xFF7FA6D9), 'Baseline eye share'),
        swatch(const Color(0xFF185ABC), 'Post eye share'),
        swatch(const Color(0xFF8A5A00), 'Comfort mean (1-5, right axis)', diamond: true),
        swatch(const Color(0xFF566666), 'Not evaluable', hollow: true),
      ],
    );
  }
}

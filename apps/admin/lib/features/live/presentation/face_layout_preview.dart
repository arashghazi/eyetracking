import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// Draws the face box, eye region and mouth region (fractions of the avatar
/// frame) inside a frame, so a researcher can see what the numbers mean.
/// A region that is not a complete box yet is left out.
class FaceLayoutPreview extends StatelessWidget {
  const FaceLayoutPreview({
    super.key,
    this.face,
    this.eye,
    this.mouth,
    this.ruleBroken = false,
    this.width = 200,
  });

  final Box? face;
  final Box? eye;
  final Box? mouth;

  /// The eye region is not above the mouth region: both are drawn in red.
  final bool ruleBroken;
  final double width;

  static const double aspect = 0.8;

  static const Color faceColor = AppColors.teal;
  static const Color eyeColor = Color(0xFF185ABC);
  static const Color mouthColor = Color(0xFF8A5A00);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eyeShown = ruleBroken ? AppColors.error : eyeColor;
    final mouthShown = ruleBroken ? AppColors.error : mouthColor;
    return Semantics(
      label: 'Preview of the face box, the eye region and the mouth region '
          'in the avatar frame',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: width / aspect,
            child: CustomPaint(
              key: const Key('face-layout-canvas'),
              painter: FaceLayoutPainter(
                face: face,
                eye: eye,
                mouth: mouth,
                faceColor: faceColor,
                eyeColor: eyeShown,
                mouthColor: mouthShown,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Legend(color: faceColor, label: 'Face', style: theme.textTheme.bodySmall),
              _Legend(color: eyeShown, label: 'Eyes', style: theme.textTheme.bodySmall),
              _Legend(color: mouthShown, label: 'Mouth', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.style});

  final Color color;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              border: Border.all(color: color),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: style),
        ],
      );
}

/// The painter behind [FaceLayoutPreview]; its boxes are readable in tests.
class FaceLayoutPainter extends CustomPainter {
  const FaceLayoutPainter({
    this.face,
    this.eye,
    this.mouth,
    required this.faceColor,
    required this.eyeColor,
    required this.mouthColor,
  });

  final Box? face;
  final Box? eye;
  final Box? mouth;
  final Color faceColor;
  final Color eyeColor;
  final Color mouthColor;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    canvas
      ..drawRect(frame, Paint()..color = AppColors.background)
      ..save()
      ..clipRect(frame);
    void draw(Box? box, Color color, {bool fill = true}) {
      if (box == null) return;
      final rect = Rect.fromLTWH(
        box.x * size.width,
        box.y * size.height,
        box.w * size.width,
        box.h * size.height,
      );
      if (fill) {
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.25));
      }
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color,
      );
    }

    draw(face, faceColor, fill: false);
    draw(eye, eyeColor);
    draw(mouth, mouthColor);
    canvas.restore();
    canvas.drawRect(
      frame.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.border,
    );
  }

  @override
  bool shouldRepaint(FaceLayoutPainter old) =>
      old.face != face ||
      old.eye != eye ||
      old.mouth != mouth ||
      old.faceColor != faceColor ||
      old.eyeColor != eyeColor ||
      old.mouthColor != mouthColor;
}

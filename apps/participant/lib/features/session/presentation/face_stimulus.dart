import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// Placeholder face: a neutral oval "face card" with simple features. It is
/// drawn inside [face] (CSS pixels of the whole screen) so the regions the
/// server classifies against line up with what the participant sees.
class FaceStimulusPainter extends CustomPainter {
  const FaceStimulusPainter(this.face);

  final Box face;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(face.x, face.y, face.w, face.h);
    canvas.drawOval(rect, Paint()..color = const Color(0xFFE7E1D8));
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFB4ACA0),
    );

    final dark = Paint()..color = const Color(0xFF4A4640);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (face.w * 0.012).clamp(1.5, 4)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF6B655C);

    final eyeY = face.y + 0.325 * face.h;
    for (final dx in const [0.30, 0.70]) {
      final cx = face.x + dx * face.w;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, eyeY),
          width: 0.15 * face.w,
          height: 0.045 * face.h,
        ),
        dark,
      );
      canvas.drawLine(
        Offset(cx - 0.08 * face.w, eyeY - 0.06 * face.h),
        Offset(cx + 0.08 * face.w, eyeY - 0.065 * face.h),
        line,
      );
    }

    final nose = Path()
      ..moveTo(face.x + 0.5 * face.w, face.y + 0.40 * face.h)
      ..lineTo(face.x + 0.47 * face.w, face.y + 0.55 * face.h)
      ..lineTo(face.x + 0.53 * face.w, face.y + 0.55 * face.h);
    canvas.drawPath(nose, line);

    final mouth = Path()
      ..moveTo(face.x + 0.38 * face.w, face.y + 0.75 * face.h)
      ..quadraticBezierTo(
        face.x + 0.5 * face.w,
        face.y + 0.78 * face.h,
        face.x + 0.62 * face.w,
        face.y + 0.75 * face.h,
      );
    canvas.drawPath(mouth, line);
  }

  @override
  bool shouldRepaint(FaceStimulusPainter old) => old.face != face;
}

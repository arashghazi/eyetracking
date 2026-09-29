import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// The placeholder face, drawn inside [face] (CSS pixels of the whole
/// screen) so the regions the server classifies against line up with what the
/// participant sees.
///
/// [level] is the face level of the gradual practice:
/// 0 a plain square, 1 a rounded face-like shape with no features,
/// 2 the low-detail face (oval, eyes, nose, mouth), 3 the same face with more
/// detail (eyebrows, iris, shading, lips). Level 3 is only the vector
/// stand-in; the approved real image, when there is one, is drawn by
/// [FaceStimulusView].
class FaceStimulusPainter extends CustomPainter {
  const FaceStimulusPainter(this.face, {this.level = 2});

  final Box face;
  final int level;

  static const _skin = Color(0xFFE7E1D8);
  static const _edge = Color(0xFFB4ACA0);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(face.x, face.y, face.w, face.h);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _edge;
    if (level <= 0) {
      canvas.drawRect(rect, Paint()..color = _skin);
      canvas.drawRect(rect, stroke);
      return;
    }
    if (level == 1) {
      final shape = RRect.fromRectAndRadius(
        rect,
        Radius.elliptical(face.w * 0.46, face.h * 0.40),
      );
      canvas.drawRRect(shape, Paint()..color = _skin);
      canvas.drawRRect(shape, stroke);
      return;
    }
    if (level >= 3) {
      _detailedFace(canvas, rect, stroke);
      return;
    }
    _lowDetailFace(canvas, rect, stroke);
  }

  Paint get _line => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = (face.w * 0.012).clamp(1.5, 4)
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFF6B655C);

  void _lowDetailFace(Canvas canvas, Rect rect, Paint stroke) {
    canvas.drawOval(rect, Paint()..color = _skin);
    canvas.drawOval(rect, stroke);

    final dark = Paint()..color = const Color(0xFF4A4640);
    final line = _line;

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

  /// The low-detail face with shading, eyebrows, irises and lips.
  void _detailedFace(Canvas canvas, Rect rect, Paint stroke) {
    final shade = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.2),
        radius: 0.95,
        colors: [Color(0xFFEFE6DA), Color(0xFFDCCFC0), Color(0xFFC9B9A6)],
        stops: [0.0, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawOval(rect, shade);
    canvas.drawOval(rect, stroke);

    final line = _line;
    final brow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (face.w * 0.022).clamp(2, 6)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4B3F35);
    final eyeY = face.y + 0.325 * face.h;
    for (final dx in const [0.30, 0.70]) {
      final cx = face.x + dx * face.w;
      final left = cx - 0.085 * face.w;
      final right = cx + 0.085 * face.w;
      // Eyebrow: an arch above the eye.
      canvas.drawPath(
        Path()
          ..moveTo(left, eyeY - 0.055 * face.h)
          ..quadraticBezierTo(
            cx, eyeY - 0.095 * face.h, right, eyeY - 0.06 * face.h),
        brow,
      );
      // Eye: white almond, iris, pupil, lid line.
      final almond = Path()
        ..moveTo(left, eyeY)
        ..quadraticBezierTo(cx, eyeY - 0.055 * face.h, right, eyeY)
        ..quadraticBezierTo(cx, eyeY + 0.045 * face.h, left, eyeY);
      canvas.drawPath(almond, Paint()..color = const Color(0xFFFAF8F4));
      canvas.drawPath(almond, line);
      final irisR = 0.026 * face.w + 0.008 * face.h;
      canvas.drawCircle(
          Offset(cx, eyeY), irisR, Paint()..color = const Color(0xFF6A5644));
      canvas.drawCircle(Offset(cx, eyeY), irisR * 0.45,
          Paint()..color = const Color(0xFF1F1B18));
    }

    // Nose with a shadow under the tip.
    final nose = Path()
      ..moveTo(face.x + 0.5 * face.w, face.y + 0.38 * face.h)
      ..quadraticBezierTo(face.x + 0.46 * face.w, face.y + 0.52 * face.h,
          face.x + 0.45 * face.w, face.y + 0.55 * face.h)
      ..quadraticBezierTo(face.x + 0.5 * face.w, face.y + 0.58 * face.h,
          face.x + 0.55 * face.w, face.y + 0.55 * face.h);
    canvas.drawPath(nose, line);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(face.x + 0.5 * face.w, face.y + 0.585 * face.h),
        width: 0.16 * face.w,
        height: 0.02 * face.h,
      ),
      Paint()..color = const Color(0x22000000),
    );

    // Lips.
    final upper = Path()
      ..moveTo(face.x + 0.37 * face.w, face.y + 0.75 * face.h)
      ..quadraticBezierTo(face.x + 0.45 * face.w, face.y + 0.715 * face.h,
          face.x + 0.5 * face.w, face.y + 0.73 * face.h)
      ..quadraticBezierTo(face.x + 0.55 * face.w, face.y + 0.715 * face.h,
          face.x + 0.63 * face.w, face.y + 0.75 * face.h)
      ..quadraticBezierTo(face.x + 0.5 * face.w, face.y + 0.765 * face.h,
          face.x + 0.37 * face.w, face.y + 0.75 * face.h);
    canvas.drawPath(upper, Paint()..color = const Color(0xFFB4746C));
    final lower = Path()
      ..moveTo(face.x + 0.37 * face.w, face.y + 0.75 * face.h)
      ..quadraticBezierTo(face.x + 0.5 * face.w, face.y + 0.80 * face.h,
          face.x + 0.63 * face.w, face.y + 0.75 * face.h);
    canvas.drawPath(
      lower,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (face.w * 0.03).clamp(3, 8)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFC08A82),
    );
  }

  @override
  bool shouldRepaint(FaceStimulusPainter old) =>
      old.face != face || old.level != level;
}

/// The face card for a face level. Level 3 shows the approved real face
/// image from [realFaceUrl] when there is one, and the detailed vector face
/// when there is none or the image cannot be loaded.
///
/// Fills the whole screen (it is positioned by the absolute coordinates of
/// [face]) and never takes pointer events.
class FaceStimulusView extends StatelessWidget {
  const FaceStimulusView({
    super.key,
    required this.face,
    this.level = 2,
    this.realFaceUrl,
  });

  final Box face;
  final int level;
  final String? realFaceUrl;

  @override
  Widget build(BuildContext context) {
    final url = realFaceUrl;
    final vector = CustomPaint(
      key: const Key('face-stimulus'),
      painter: FaceStimulusPainter(face, level: level),
    );
    if (level < 3 || url == null || url.isEmpty) {
      return IgnorePointer(child: SizedBox.expand(child: vector));
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Drawn first so it shows while the photo loads or if it fails.
          vector,
          Positioned(
            left: face.x,
            top: face.y,
            width: face.w,
            height: face.h,
            child: ClipOval(
              child: Image.network(
                url,
                key: const Key('face-real-image'),
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                frameBuilder: (context, child, frame, sync) =>
                    frame == null && !sync ? const SizedBox.shrink() : child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

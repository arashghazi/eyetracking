import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A plain picture symbol for the symbol response mode: circle, square,
/// triangle or star.
class SymbolGlyph extends StatelessWidget {
  const SymbolGlyph({
    super.key,
    required this.name,
    this.size = 32,
    this.color = const Color(0xFF1E2B2B),
  });

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: name,
        child: CustomPaint(
          size: Size.square(size),
          painter: _SymbolPainter(name, color),
        ),
      );
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter(this.name, this.color);

  final String name;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = Offset.zero & size;
    switch (name) {
      case 'circle':
        canvas.drawCircle(r.center, size.width * 0.46, paint);
      case 'square':
        canvas.drawRect(r.deflate(size.width * 0.08), paint);
      case 'triangle':
        canvas.drawPath(
          Path()
            ..moveTo(r.center.dx, size.height * 0.06)
            ..lineTo(size.width * 0.94, size.height * 0.92)
            ..lineTo(size.width * 0.06, size.height * 0.92)
            ..close(),
          paint,
        );
      default:
        final path = Path();
        final c = r.center;
        final outer = size.width * 0.48, inner = size.width * 0.20;
        for (var i = 0; i < 10; i++) {
          final radius = i.isEven ? outer : inner;
          final angle = -math.pi / 2 + i * math.pi / 5;
          final p = Offset(c.dx + radius * math.cos(angle),
              c.dy + radius * math.sin(angle));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), paint);
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.name != name || old.color != color;
}

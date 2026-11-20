import 'dart:math' as math;
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// Animated orange geometric shapes (rounded squares, rings, dots)
/// that drift slowly behind content — 10-second sine-wave loop.
class FloatingShapes extends StatefulWidget {
  final Widget child;

  const FloatingShapes({
    super.key,
    required this.child,
  });

  @override
  State<FloatingShapes> createState() => _FloatingShapesState();
}

class _FloatingShapesState extends State<FloatingShapes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ShapePainter(t: _controller.value * 2 * math.pi),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

enum _ShapeKind { roundedSquare, ring, dot }

class _ShapeDef {
  final double x;      // relative 0..1
  final double y;
  final double size;
  final double alpha;
  final double driftAmp;
  final double driftPhase;
  final double rotateSpeed; // rotations per loop
  final _ShapeKind kind;

  const _ShapeDef({
    required this.x,
    required this.y,
    required this.size,
    required this.alpha,
    required this.driftAmp,
    required this.driftPhase,
    required this.rotateSpeed,
    required this.kind,
  });
}

const _shapes = [
  // Rounded squares
  _ShapeDef(x: 0.08, y: 0.12, size: 32, alpha: 0.10, driftAmp: 18, driftPhase: 0.0,  rotateSpeed: 0.25, kind: _ShapeKind.roundedSquare),
  _ShapeDef(x: 0.85, y: 0.20, size: 24, alpha: 0.08, driftAmp: 14, driftPhase: 1.3,  rotateSpeed: -0.15, kind: _ShapeKind.roundedSquare),
  _ShapeDef(x: 0.50, y: 0.70, size: 40, alpha: 0.09, driftAmp: 22, driftPhase: 2.7,  rotateSpeed: 0.18, kind: _ShapeKind.roundedSquare),
  _ShapeDef(x: 0.70, y: 0.55, size: 20, alpha: 0.12, driftAmp: 10, driftPhase: 4.1,  rotateSpeed: -0.3, kind: _ShapeKind.roundedSquare),
  _ShapeDef(x: 0.25, y: 0.80, size: 28, alpha: 0.08, driftAmp: 16, driftPhase: 5.5,  rotateSpeed: 0.2,  kind: _ShapeKind.roundedSquare),
  // Rings
  _ShapeDef(x: 0.15, y: 0.45, size: 48, alpha: 0.12, driftAmp: 12, driftPhase: 0.8,  rotateSpeed: 0.1,  kind: _ShapeKind.ring),
  _ShapeDef(x: 0.78, y: 0.72, size: 36, alpha: 0.10, driftAmp: 20, driftPhase: 2.0,  rotateSpeed: -0.08, kind: _ShapeKind.ring),
  _ShapeDef(x: 0.55, y: 0.30, size: 56, alpha: 0.08, driftAmp: 8,  driftPhase: 3.4,  rotateSpeed: 0.06, kind: _ShapeKind.ring),
  // Dots
  _ShapeDef(x: 0.35, y: 0.15, size: 7,  alpha: 0.15, driftAmp: 10, driftPhase: 1.6,  rotateSpeed: 0.0,  kind: _ShapeKind.dot),
  _ShapeDef(x: 0.90, y: 0.40, size: 5,  alpha: 0.12, driftAmp: 12, driftPhase: 3.0,  rotateSpeed: 0.0,  kind: _ShapeKind.dot),
  _ShapeDef(x: 0.60, y: 0.88, size: 8,  alpha: 0.10, driftAmp: 14, driftPhase: 4.8,  rotateSpeed: 0.0,  kind: _ShapeKind.dot),
  _ShapeDef(x: 0.05, y: 0.65, size: 6,  alpha: 0.13, driftAmp: 9,  driftPhase: 6.0,  rotateSpeed: 0.0,  kind: _ShapeKind.dot),
];

class _ShapePainter extends CustomPainter {
  final double t; // 0..2π

  const _ShapePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    for (final s in _shapes) {
      final dx = math.sin(t + s.driftPhase) * s.driftAmp;
      final dy = math.cos(t * 0.7 + s.driftPhase) * s.driftAmp * 0.6;
      final cx = size.width * s.x + dx;
      final cy = size.height * s.y + dy;
      final angle = t * s.rotateSpeed * math.pi * 2;

      paint.color = kOrange500.withValues(alpha: s.alpha);

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);

      switch (s.kind) {
        case _ShapeKind.roundedSquare:
          paint.style = PaintingStyle.fill;
          final r = s.size / 2;
          final rrect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: s.size, height: s.size),
            Radius.circular(r * 0.35),
          );
          canvas.drawRRect(rrect, paint);
          break;

        case _ShapeKind.ring:
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 1.5;
          canvas.drawCircle(Offset.zero, s.size / 2, paint);
          break;

        case _ShapeKind.dot:
          paint.style = PaintingStyle.fill;
          canvas.drawCircle(Offset.zero, s.size / 2, paint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) => old.t != t;
}

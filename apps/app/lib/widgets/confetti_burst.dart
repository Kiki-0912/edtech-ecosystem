import 'dart:math' as math;
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// "Flame Burst" — 24 orange/amber/white particles radiate outward then
/// fall under gravity. Trigger by calling [ConfettiBurstController.fire].
class ConfettiBurst extends StatefulWidget {
  final Widget child;
  final ConfettiBurstController controller;

  const ConfettiBurst({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    widget.controller._attach(_fire);
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _particles = []);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._detach();
      widget.controller._attach(_fire);
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    _anim.dispose();
    super.dispose();
  }

  void _fire() {
    final rng = math.Random();
    final colors = [kOrange200, kOrange300, kOrange400, kOrange500, Colors.white];
    _particles = List.generate(24, (i) {
      final angle = (i / 24) * 2 * math.pi;
      final speed = 0.5 + rng.nextDouble() * 0.5;
      return _Particle(
        angle: angle,
        speed: speed,
        color: colors[rng.nextInt(colors.length)],
        size: 4.0 + rng.nextDouble() * 6.0,
        isSquare: rng.nextBool(),
        spin: (rng.nextDouble() - 0.5) * 6,
      );
    });
    _anim.forward(from: 0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_particles.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => CustomPaint(
                  painter: _FlamePainter(
                    particles: _particles,
                    progress: _anim.value,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class ConfettiBurstController {
  VoidCallback? _fire;

  void _attach(VoidCallback fire) => _fire = fire;
  void _detach() => _fire = null;

  void fire() => _fire?.call();
}

// ---------------------------------------------------------------------------

class _Particle {
  final double angle;
  final double speed;
  final Color color;
  final double size;
  final bool isSquare;
  final double spin;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.isSquare,
    required this.spin,
  });
}

class _FlamePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress; // 0..1

  const _FlamePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Ease-out for radial travel; linear for gravity drop.
    final eased = Curves.easeOut.transform(progress);
    const gravity = 300.0; // pixels

    for (final p in particles) {
      final radius = eased * p.speed * size.height * 0.42;
      final px = cx + math.cos(p.angle) * radius;
      final py = cy + math.sin(p.angle) * radius + gravity * progress * progress * p.speed;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      paint.color = p.color.withValues(alpha: opacity);
      paint.style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.spin * progress);

      if (p.isSquare) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) =>
      old.progress != progress;
}

import 'dart:math' as math;

import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Motion tokens. Every animation in the app uses these, so it all feels like
/// the same hand made it. All of them collapse to zero when the platform asks
/// for reduced motion (see [AppMotion.of]).
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 450);

  /// Delay between consecutive items in a staggered entrance.
  static const Duration stagger = Duration(milliseconds: 40);

  /// Items beyond this index appear without a delay.
  static const int maxStagger = 8;

  static const Curve standard = Curves.easeOutCubic;

  /// Gentle overshoot for success moments and pops.
  static const Curve pop = Curves.easeOutBack;

  /// True when animations should be skipped.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d] unless reduced motion is on, then zero.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

  /// Delay for item [index] in a staggered list.
  static Duration delayFor(int index) =>
      stagger * math.min(index, maxStagger).toInt();
}

/// Fades and rises its child into place once, when first built. An optional
/// [delay] staggers siblings. Uses a single controller (no timers), so tests
/// can settle.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 16,
    this.duration = AppMotion.base,
  });

  final Widget child;
  final Duration delay;

  /// Starting distance below the final position, in logical pixels.
  final double offset;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + widget.duration;
    _controller = AnimationController(vsync: this, duration: total);
    final start = total.inMilliseconds == 0
        ? 0.0
        : widget.delay.inMilliseconds / total.inMilliseconds;
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: AppMotion.standard),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.offset),
          child: child,
        ),
      ),
    );
  }
}

/// Press feel: scales the child down slightly while a pointer is on it and
/// springs back. Does not take part in gestures, so it composes with InkWell,
/// buttons and anything else tappable.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: AppMotion.of(context, AppMotion.fast),
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}

/// Text that counts up to its number the first time it is shown. Keeps any
/// prefix, suffix, decimals and thousands separators of [value] ("92%",
/// "1,240", "3.5 h"). Text with no number is shown as is.
class CountUpText extends StatelessWidget {
  const CountUpText(
    this.value, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String value;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  static final RegExp _number = RegExp(r'^(\D*?)(\d[\d,]*(?:\.\d+)?)(.*)$');

  /// "1240" -> "1,240" when [grouped].
  static String _format(double n, int decimals, bool grouped) {
    final fixed = n.toStringAsFixed(decimals);
    if (!grouped) return fixed;
    final parts = fixed.split('.');
    final digits = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return parts.length > 1 ? '$buffer.${parts[1]}' : buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final match = _number.firstMatch(value);
    if (match == null || AppMotion.reduced(context)) {
      return Text(value, style: style, maxLines: maxLines, overflow: overflow);
    }
    final prefix = match.group(1)!;
    final raw = match.group(2)!;
    final suffix = match.group(3)!;
    final target = double.tryParse(raw.replaceAll(',', ''));
    if (target == null) {
      return Text(value, style: style, maxLines: maxLines, overflow: overflow);
    }
    final decimals = raw.contains('.') ? raw.split('.').last.length : 0;
    final grouped = raw.contains(',');
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: AppMotion.slow * 1.5,
      curve: AppMotion.standard,
      builder: (context, v, _) => Text(
        '$prefix${_format(v, decimals, grouped)}$suffix',
        style: style?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// A checkmark that draws itself. Plays once; [color] defaults to the accent.
class AnimatedCheck extends StatelessWidget {
  const AnimatedCheck({super.key, this.size = 24, this.color, this.stroke = 3});

  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.standard,
      builder: (context, t, _) => CustomPaint(
        size: Size.square(size),
        painter: _CheckPainter(
          progress: t,
          color: color ?? context.colors.accent,
          stroke: stroke,
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.progress,
    required this.color,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.54)
      ..lineTo(size.width * 0.42, size.height * 0.76)
      ..lineTo(size.width * 0.84, size.height * 0.28);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// Six small dots that burst outward once and fade: the "it worked" sparkle.
class SuccessBurst extends StatelessWidget {
  const SuccessBurst({super.key, this.size = 72, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dot = color ?? context.colors.accent;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context, const Duration(milliseconds: 600)),
        curve: AppMotion.standard,
        builder: (context, t, _) => CustomPaint(
          size: Size.square(size),
          painter: _BurstPainter(t: t, color: dot),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final paint = Paint()..color = color.withValues(alpha: (1 - t) * 0.9);
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 - math.pi / 2;
      final distance = radius * (0.35 + 0.65 * t);
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * distance,
        3.5 * (1 - t * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}

/// Page transition for pushed routes: a quick fade with a small rise.
class SoftRiseTransitionsBuilder extends PageTransitionsBuilder {
  const SoftRiseTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: AppMotion.standard);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}

/// Replays a short fade and rise whenever [token] changes, without remounting
/// [child] (so navigator and scroll state survive). Used for tab switches.
class SwitchFade extends StatefulWidget {
  const SwitchFade({super.key, required this.token, required this.child});

  final Object token;
  final Widget child;

  @override
  State<SwitchFade> createState() => _SwitchFadeState();
}

class _SwitchFadeState extends State<SwitchFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.base, value: 1);
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: AppMotion.standard);

  @override
  void didUpdateWidget(SwitchFade old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token && !AppMotion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: 0.4 + 0.6 * _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * 12),
          child: child,
        ),
      ),
    );
  }
}

/// Lifts its child a few pixels with a soft warm shadow while a mouse hovers
/// it (web and desktop). Does nothing on touch.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.lift = 4});

  final Widget child;
  final double lift;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.fast),
        curve: AppMotion.standard,
        transform: Matrix4.translationValues(0, _hover ? -widget.lift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: AppRadius.lgAll,
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: c.accentGlow.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

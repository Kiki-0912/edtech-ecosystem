import 'package:flutter/material.dart';

/// NOIR FLAME skeleton loader.
///
/// Dark mode:  `0xFF1A1A1A` → `0xFF282828` → `0xFF1A1A1A`
/// Light mode: `0xFFE8E8E8` → `0xFFF5F5F5` → `0xFFE8E8E8`
///
/// A subtle orange tint bleeds in at the shimmer's brightest point,
/// giving the "flame scan" feel that keeps the NOIR FLAME identity.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Base colours
    final Color baseA = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8);
    final Color baseB = isDark ? const Color(0xFF282828) : const Color(0xFFF5F5F5);

    // Flame-tinted peak colour — a faint orange whisper at the shimmer centre.
    const Color flamePeak = Color(0x14FF6B00); // orange at ~8 % opacity

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // We want three stops that sweep left → right.
        // Guard so stops are always ascending and within [0, 1].
        final double s0 = (t - 0.35).clamp(0.0, 1.0);
        final double s1 = t.clamp(0.0, 1.0);
        final double s2 = (t + 0.35).clamp(0.0, 1.0);

        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseA,
                baseB,
                // Blend a tiny orange tint at the peak so it reads as a
                // "flame scan" without breaking the black/white/orange rule.
                Color.alphaBlend(flamePeak, baseB),
                baseB,
                baseA,
              ],
              stops: [0.0, s0, s1, s2, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: baseA,
              borderRadius: widget.borderRadius,
            ),
          ),
        );
      },
    );
  }
}

/// A full skeleton card shaped like a [CourseCard] / content tile.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF282828) : const Color(0xFFE8E8E8);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonBox(
                width: 56,
                height: 22,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              const Spacer(),
              SkeletonBox(
                width: 20,
                height: 20,
                borderRadius: BorderRadius.circular(10),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(width: 200, height: 18),
          const SizedBox(height: 8),
          const SkeletonBox(width: 130, height: 12),
          const SizedBox(height: 16),
          const Row(
            children: [
              SkeletonBox(width: 70, height: 14),
              SizedBox(width: 16),
              SkeletonBox(width: 80, height: 14),
            ],
          ),
        ],
      ),
    );
  }
}

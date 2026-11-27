import 'package:edtech_app/ui/motion.dart';
import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Logo: the Edu-tech mark (graduation cap on a book) on its own light tile,
/// so the black artwork stays visible in dark mode; optionally with the name.
class BrandMark extends StatelessWidget {
  const BrandMark(
      {super.key, this.showName = true, this.size = 36, this.nameColor});

  final bool showName;
  final double size;

  /// Overrides the name colour (e.g. on the ink-black auth panel).
  final Color? nameColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: AppRadius.mdAll,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.mdAll,
        child: Image.asset(
          'assets/images/logo_mark.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Edu-tech Ecosystem logo',
        ),
      ),
    );
    // A small pop with a playful tilt as it settles.
    final mark = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.slow * 1.4),
      curve: AppMotion.pop,
      builder: (context, t, child) => Transform.rotate(
        angle: (1 - t) * -0.35,
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: tile,
    );
    if (!showName) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: AppSpacing.sm),
        Text('Edu-tech',
            style: context.text.titleLarge?.copyWith(color: nameColor)),
      ],
    );
  }
}

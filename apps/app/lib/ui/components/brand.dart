import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Logo: the Edu-tech mark (graduation cap on a book) on its own light tile,
/// so the black artwork stays visible in dark mode; optionally with the name.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.showName = true, this.size = 36});

  final bool showName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mark = Container(
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
    if (!showName) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: AppSpacing.sm),
        Text('EdTech', style: context.text.titleLarge),
      ],
    );
  }
}

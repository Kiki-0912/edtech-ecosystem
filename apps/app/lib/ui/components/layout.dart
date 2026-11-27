import 'package:edtech_app/ui/motion.dart';
import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Standard page body: scrollable, centred, max-width constrained, with a
/// [PageHeader] and optional pull-to-refresh.
///
/// Pages live inside the app shell (which owns the Scaffold / app bar), so this
/// is not a Scaffold. Use [AppPage.slivers] for long lists.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.children = const [],
    this.onRefresh,
    this.bottom,
    this.slivers,
    this.maxWidth = Breakpoints.maxContent,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// Pinned widget under the scroll view (e.g. a sticky save bar).
  final Widget? bottom;

  /// When provided, rendered after the header instead of [children].
  final List<Widget>? slivers;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final hPad = context.isCompact ? AppSpacing.md : AppSpacing.lg;

    // Full width up to [maxWidth], centred beyond it. The SizedBox matters:
    // without it, short content (headers, chip rows) shrink-wraps and centres.
    Widget constrain(Widget child) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox(width: double.infinity, child: child),
          ),
        );

    final header =
        PageHeader(title: title, subtitle: subtitle, actions: actions);

    Widget scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(hPad, AppSpacing.lg, hPad, AppSpacing.md),
          sliver: SliverToBoxAdapter(
              child: FadeSlideIn(offset: 8, child: constrain(header))),
        ),
        if (slivers != null)
          ...slivers!.map((s) => SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                sliver:
                    SliverCrossAxisConstrained(maxWidth: maxWidth, sliver: s),
              ))
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            sliver: SliverList.separated(
              itemCount: children.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.lg),
              // The first few sections rise in one after another; the rest
              // are built as you scroll, so they appear without ceremony.
              itemBuilder: (_, i) => i < AppMotion.maxStagger
                  ? FadeSlideIn(
                      delay: AppMotion.delayFor(i + 1),
                      child: constrain(children[i]),
                    )
                  : constrain(children[i]),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );

    if (onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: onRefresh!, child: scroll);
    }

    return ColoredBox(
      color: context.colors.background,
      child: Column(
        children: [
          Expanded(child: scroll),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}

/// Centres a sliver and limits its width (sliver counterpart of ConstrainedBox).
class SliverCrossAxisConstrained extends StatelessWidget {
  const SliverCrossAxisConstrained({
    super.key,
    required this.maxWidth,
    required this.sliver,
  });

  final double maxWidth;
  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final extra = constraints.crossAxisExtent - maxWidth;
      final pad = extra > 0 ? extra / 2 : 0.0;
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        sliver: sliver,
      );
    });
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: context.isCompact
                ? context.text.headlineSmall
                : context.text.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle!, style: context.text.bodyMedium),
        ],
      ],
    );

    if (actions.isEmpty) return titleBlock;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.sm,
      spacing: AppSpacing.md,
      children: [
        titleBlock,
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium),
                if (subtitle != null)
                  Text(subtitle!, style: context.text.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Grid that picks a column count from the available width.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 280,
    this.spacing = AppSpacing.md,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Never create more columns than items, so a short row fills the width.
      final columns =
          ((constraints.maxWidth + spacing) / (minItemWidth + spacing))
              .floor()
              .clamp(1, children.isEmpty ? 1 : children.length.clamp(1, 6));
      final itemWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(
              width: itemWidth,
              child: FadeSlideIn(
                delay: AppMotion.delayFor(i),
                offset: 12,
                child: children[i],
              ),
            ),
        ],
      );
    });
  }
}

/// Side-by-side on wide screens, stacked on narrow ones.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.breakpoint = 900,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [primary, const SizedBox(height: AppSpacing.lg), secondary],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: primaryFlex, child: primary),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: secondaryFlex, child: secondary),
        ],
      );
    });
  }
}

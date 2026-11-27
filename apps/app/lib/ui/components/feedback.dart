import 'dart:math' as math;

import 'package:edtech_app/ui/components/illustrations.dart';
import 'package:edtech_app/ui/motion.dart';
import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Centred icon + message + optional action. Used for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.illustration,
  });

  /// When set, a line drawing replaces the icon badge.
  final IllustrationKind? illustration;
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FadeSlideIn(
        child: Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl, horizontal: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (illustration != null)
            LineIllustration(kind: illustration!)
          else
            // The icon pops in with a small overshoot, then rests.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: AppMotion.of(context, AppMotion.slow),
              curve: AppMotion.pop,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: c.accentText, size: 30),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(title,
              style: context.text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(message!,
                style: context.text.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    ));
  }
}

/// Error message with a retry button.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl, horizontal: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LineIllustration(kind: IllustrationKind.error, size: 88),
          const SizedBox(height: AppSpacing.md),
          Text(title,
              style: context.text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xxs),
          Text(friendlyError(message),
              style: context.text.bodyMedium, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline error message for forms and sign-in pages, where a toast would be
/// hidden behind a bottom sheet or dialog.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A single quick shake as it appears, so errors are noticed but not nagging.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.slow),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 4) * 6 * (1 - t), 0),
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration:
            BoxDecoration(color: c.dangerSoft, borderRadius: AppRadius.mdAll),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(message,
                  style:
                      context.text.bodyMedium?.copyWith(color: c.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Strips noisy exception prefixes for display.
String friendlyError(Object error) {
  var s = error.toString();
  for (final prefix in ['Exception: ', 'ApiException: ', 'Bad state: ']) {
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
  }
  // On the web, package:http reports an unreachable server or a CORS refusal
  // as `ClientException: Failed to fetch, uri=...`.
  if (s.contains('SocketException') ||
      s.contains('TimeoutException') ||
      s.contains('ClientException') ||
      s.contains('Failed to fetch')) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return s;
}

/// Placeholder block with a soft warm pulse. The pulse runs a handful of
/// times and then rests, so a stuck load never animates forever and tests can
/// settle.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!AppMotion.reduced(context)) {
      _controller.repeat(reverse: true, count: 6);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(c.surfaceMuted, c.border,
              Curves.easeInOut.transform(_controller.value)),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A list of card-shaped skeletons for loading states.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.itemHeight = 72});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            Skeleton(height: itemHeight, radius: AppRadius.lg),
            if (i != count - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// Loading / error / empty / data switch for a single async load.
///
/// The owning State keeps `loading`, `error` and the data; this widget only
/// decides what to render so every screen behaves the same way.
class AsyncBody extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.loading,
    required this.error,
    required this.isEmpty,
    required this.builder,
    this.onRetry,
    this.empty,
    this.skeleton,
  });

  final bool loading;
  final Object? error;
  final bool isEmpty;
  final WidgetBuilder builder;
  final VoidCallback? onRetry;
  final Widget? empty;
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    if (loading) return skeleton ?? const SkeletonList();
    if (error != null) {
      return ErrorState(message: friendlyError(error!), onRetry: onRetry);
    }
    if (isEmpty) {
      return empty ??
          const EmptyState(
              icon: Icons.inbox_outlined, title: 'Nothing here yet');
    }
    return builder(context);
  }
}

enum ToastKind { info, success, error }

void showToast(BuildContext context, String message,
    {ToastKind kind = ToastKind.info}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final c = context.colors;
  final icon = switch (kind) {
    ToastKind.success => Icons.check_circle_rounded,
    ToastKind.error => Icons.error_rounded,
    ToastKind.info => Icons.info_rounded,
  };
  final iconColor = switch (kind) {
    ToastKind.success => c.success,
    ToastKind.error => c.danger,
    ToastKind.info => c.accent,
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          if (kind == ToastKind.success)
            SizedBox.square(
              dimension: 28,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  const OverflowBox(
                    maxWidth: 44,
                    maxHeight: 44,
                    child: SuccessBurst(size: 44),
                  ),
                  DecoratedBox(
                    decoration:
                        BoxDecoration(color: c.success, shape: BoxShape.circle),
                    child: SizedBox.square(
                      dimension: 22,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: AnimatedCheck(
                            size: 16, color: c.surface, stroke: 2.4),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    ));
}

/// Confirmation dialog. Returns true when the user confirms.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
        ),
        FilledButton(
          key: const Key('confirm-dialog-ok'),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: c.danger, foregroundColor: c.surface)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

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
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl, horizontal: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: c.textMuted, size: 28),
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
    );
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
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl, horizontal: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration:
                BoxDecoration(color: c.dangerSoft, shape: BoxShape.circle),
            child: Icon(Icons.error_outline_rounded, color: c.danger, size: 28),
          ),
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

/// Strips noisy exception prefixes for display.
String friendlyError(Object error) {
  var s = error.toString();
  for (final prefix in ['Exception: ', 'ApiException: ', 'Bad state: ']) {
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
  }
  if (s.contains('SocketException') || s.contains('TimeoutException')) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return s;
}

/// Static placeholder block (no endless animation, so tests can settle).
class Skeleton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
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

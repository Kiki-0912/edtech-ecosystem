import 'package:edtech_app/formats.dart';
import 'package:edtech_app/ui/motion.dart';
import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.controller,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
      ),
    );
  }
}

class FilterOption<T> {
  const FilterOption(this.value, this.label);
  final T value;
  final String label;
}

/// Horizontally scrollable single-select chips.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: ChoiceChip(
                label: Text(o.label),
                selected: o.value == selected,
                onSelected: (_) => onSelected(o.value),
                labelStyle: context.text.labelMedium?.copyWith(
                  color: o.value == selected ? c.accentText : c.textSecondary,
                  fontWeight:
                      o.value == selected ? FontWeight.w600 : FontWeight.w500,
                ),
                side: BorderSide(
                    color: o.value == selected ? c.accent : c.border),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens a form as a bottom sheet on phones and a dialog on wider screens.
///
/// [builder] receives the sheet context; pop it with a result to close.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  if (context.isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + AppSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: ctx.text.titleLarge),
              const SizedBox(height: AppSpacing.md),
              builder(ctx),
            ],
          ),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: ctx.text.titleLarge)),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              builder(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Read-only field that opens a date picker.
class DatePickerField extends StatelessWidget {
  const DatePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: firstDate ?? DateTime(2020),
          lastDate: lastDate ?? DateTime(2035),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
          isDense: true,
        ),
        child: Text(shortDate(value), style: context.text.bodyLarge),
      ),
    );
  }
}

/// Read-only field that opens a time picker.
class TimePickerField extends StatelessWidget {
  const TimePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: () async {
        final picked =
            await showTimePicker(context: context, initialTime: value);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule_rounded, size: 18),
          isDense: true,
        ),
        child: Text(value.format(context), style: context.text.bodyLarge),
      ),
    );
  }
}

/// Primary submit button with a built-in busy spinner.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.fast),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: busy
          ? SizedBox(
              key: const ValueKey('busy'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.colors.onAccent),
            )
          : Text(label, key: const ValueKey('label')),
    );
    if (icon != null && !busy) {
      return Pressable(
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: child,
        ),
      );
    }
    return Pressable(
      child: FilledButton(onPressed: busy ? null : onPressed, child: child),
    );
  }
}

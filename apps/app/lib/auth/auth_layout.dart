import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Shared frame for sign-in, sign-up and SMS verification.
///
/// Wide screens: brand panel on the left, form card on the right.
/// Phones: brand mark above a single centred form.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: FadeSlideIn(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!wide) ...[
            const Align(alignment: Alignment.centerLeft, child: BrandMark()),
            const SizedBox(height: AppSpacing.xl),
          ],
          if (onBack != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back'),
                style: TextButton.styleFrom(
                    foregroundColor: c.textSecondary, padding: EdgeInsets.zero),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(title, style: context.text.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          child,
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.lg),
            footer!,
          ],
        ],
      )),
    );

    final formPane = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
        child: form,
      ),
    );

    return Scaffold(
      backgroundColor: wide ? c.surface : c.background,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  const Expanded(flex: 5, child: _BrandPanel()),
                  Expanded(flex: 6, child: formPane),
                ],
              )
            : formPane,
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onInk = c.onInk;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: AppRadius.xlAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // A big soft orange glow rising from the corner: the one spark.
          Positioned(
            right: -160,
            bottom: -160,
            child: IgnorePointer(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c.accent.withValues(alpha: 0.55),
                      c.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandMark(nameColor: onInk),
                const Spacer(),
                FadeSlideIn(
                  delay: AppMotion.delayFor(1),
                  child: Text('Your classroom,\nall in one place.',
                      style: context.text.displaySmall?.copyWith(color: onInk)),
                ),
                const SizedBox(height: AppSpacing.md),
                FadeSlideIn(
                  delay: AppMotion.delayFor(2),
                  child: Text(
                    'Courses, attendance, schedules, chat and process-based '
                    'integrity insights for students, teachers and administrators.',
                    style: context.text.bodyLarge
                        ?.copyWith(color: onInk.withValues(alpha: 0.72)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FadeSlideIn(
                  delay: AppMotion.delayFor(3),
                  child: const _Feature(
                      icon: Icons.fact_check_outlined,
                      text: 'Mark and review attendance in seconds'),
                ),
                FadeSlideIn(
                  delay: AppMotion.delayFor(4),
                  child: const _Feature(
                      icon: Icons.calendar_month_outlined,
                      text: 'Classes, quizzes and deadlines on one calendar'),
                ),
                FadeSlideIn(
                  delay: AppMotion.delayFor(5),
                  child: const _Feature(
                      icon: Icons.verified_user_outlined,
                      text: 'Effort insights that respect student privacy'),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          IconBadge(icon: icon, size: 36),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(text,
                  style: context.text.titleSmall
                      ?.copyWith(color: context.colors.onInk))),
        ],
      ),
    );
  }
}

/// Password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
    this.autofillHints = const [AutofillHints.password],
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  /// The signed-in person's own password by default. Use
  /// [AutofillHints.newPassword] for a password being set for someone else,
  /// so password managers neither fill nor overwrite the saved one.
  final List<String> autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

String? requiredField(String? value, String message) =>
    (value == null || value.trim().isEmpty) ? message : null;

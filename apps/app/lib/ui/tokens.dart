import 'package:material_ui/material_ui.dart';

/// Design tokens for the EdTech design system.
///
/// Screens must read colours through [AppColorsX.colors] (`context.colors`) and
/// spacing / radii through [AppSpacing] / [AppRadius]. No raw hex values, no
/// `Colors.*` and no literal font sizes in screens.

/// Brand orange. Used as a *fill* (buttons, active nav, progress), never as
/// body text on light surfaces (contrast is too low): use [AppColors.accentText].
const Color kBrandOrange = Color(0xFFFF6B00);

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentText,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.overlay,
    required this.accentGlow,
    required this.inkSoft,
    required this.ink,
    required this.onInk,
  });

  /// Page background.
  final Color background;

  /// Cards, sheets, app bars.
  final Color surface;

  /// Subtle fills: inputs, table headers, chips, skeletons.
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Brand fill and the colour drawn on top of it.
  final Color accent;
  final Color onAccent;

  /// Tinted brand background (selected rows, active nav pill).
  final Color accentSoft;

  /// Brand colour that is legible as text/icon on [surface].
  final Color accentText;

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  /// Scrim behind modal content.
  final Color overlay;

  /// Soft orange halo for focus rings and hover glows.
  final Color accentGlow;

  /// Faint ink wash for pressed and hovered states.
  final Color inkSoft;

  /// Near-black brand surface (auth panel, hero moments) and its text colour.
  /// Identical in light and dark mode.
  final Color ink;
  final Color onInk;

  static const light = AppColors(
    background: Color(0xFFFAFAF9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F5F4),
    border: Color(0xFFE7E5E4),
    textPrimary: Color(0xFF1C1917),
    textSecondary: Color(0xFF57534E),
    textMuted: Color(0xFF78716C),
    accent: kBrandOrange,
    onAccent: Color(0xFF1C1917),
    accentSoft: Color(0xFFFFF1E6),
    accentText: Color(0xFFC2410C),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFDCFCE7),
    warning: Color(0xFFCA8A04),
    warningSoft: Color(0xFFFEF9C3),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEE2E2),
    info: Color(0xFF0284C7),
    infoSoft: Color(0xFFE0F2FE),
    overlay: Color(0x661C1917),
    accentGlow: Color(0x4DFF6B00),
    inkSoft: Color(0x0A1C1917),
    ink: Color(0xFF1C1917),
    onInk: Color(0xFFFAFAF9),
  );

  static const dark = AppColors(
    background: Color(0xFF0C0A09),
    surface: Color(0xFF1C1917),
    surfaceMuted: Color(0xFF292524),
    border: Color(0xFF292524),
    textPrimary: Color(0xFFFAFAF9),
    textSecondary: Color(0xFFD6D3D1),
    textMuted: Color(0xFFA8A29E),
    accent: kBrandOrange,
    onAccent: Color(0xFF1C1917),
    accentSoft: Color(0xFF3A1F0B),
    accentText: Color(0xFFFB923C),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF14321F),
    warning: Color(0xFFFACC15),
    warningSoft: Color(0xFF3A3010),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3B1414),
    info: Color(0xFF38BDF8),
    infoSoft: Color(0xFF0C2A3B),
    overlay: Color(0x99000000),
    accentGlow: Color(0x66FF6B00),
    inkSoft: Color(0x14FAFAF9),
    ink: Color(0xFF1C1917),
    onInk: Color(0xFFFAFAF9),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      accentText: l(accentText, other.accentText),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      info: l(info, other.info),
      infoSoft: l(infoSoft, other.infoSoft),
      overlay: l(overlay, other.overlay),
      accentGlow: l(accentGlow, other.accentGlow),
      inkSoft: l(inkSoft, other.inkSoft),
      ink: l(ink, other.ink),
      onInk: l(onInk, other.onInk),
    );
  }
}

/// Semantic tones used by badges, stat tiles and status indicators.
enum Tone { neutral, accent, success, warning, danger, info }

extension ToneColors on AppColors {
  Color fg(Tone tone) => switch (tone) {
        Tone.neutral => textSecondary,
        Tone.accent => accentText,
        Tone.success => success,
        Tone.warning => warning,
        Tone.danger => danger,
        Tone.info => info,
      };

  Color bg(Tone tone) => switch (tone) {
        Tone.neutral => surfaceMuted,
        Tone.accent => accentSoft,
        Tone.success => successSoft,
        Tone.warning => warningSoft,
        Tone.danger => dangerSoft,
        Tone.info => infoSoft,
      };
}

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Layout breakpoints (logical pixels).
abstract final class Breakpoints {
  /// Below this: phone layout, bottom navigation bar.
  static const double compact = 600;

  /// Below this: navigation rail. At or above: full sidebar, two-pane layouts.
  static const double expanded = 1024;

  /// Max content width for pages.
  static const double maxContent = 1200;
}

enum WindowSize { compact, medium, expanded }

extension AppContextX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;

  TextTheme get text => Theme.of(this).textTheme;

  WindowSize get windowSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width < Breakpoints.compact) return WindowSize.compact;
    if (width < Breakpoints.expanded) return WindowSize.medium;
    return WindowSize.expanded;
  }

  bool get isCompact => windowSize == WindowSize.compact;
}

/// Soft elevation used by cards that need to float (menus, sticky bars).
List<BoxShadow> appShadow(AppColors c) => [
      BoxShadow(
        color: c.textPrimary.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];

import 'package:flutter/material.dart';

/// NOIR FLAME design system — dark academic meets streetwear energy.
/// Strict orange / black / white palette only. Zero pastels, zero blues,
/// zero greens. Every constant and getter name is preserved for
/// source-compatibility with the rest of the codebase.

/* ============================================================
   Orange family
   ============================================================ */

const kOrange50  = Color(0xFFFFF3E0);
const kOrange100 = Color(0xFFFFE0B2);
const kOrange200 = Color(0xFFFFCC80);
const kOrange300 = Color(0xFFFFB347);
const kOrange400 = Color(0xFFFF9500);
const kOrange500 = Color(0xFFFF6B00); // PRIMARY
const kOrange600 = Color(0xFFE55A00);
const kOrange700 = Color(0xFFCC4500);
const kOrange800 = Color(0xFF993300);
const kOrange900 = Color(0xFF5C1A00);

/* ============================================================
   Blacks & whites
   ============================================================ */

const kBlack50  = Color(0xFFF7F7F7);
const kBlack100 = Color(0xFFE8E8E8);
const kBlack200 = Color(0xFFD0D0D0);
const kBlack300 = Color(0xFF9A9A9A);
const kBlack400 = Color(0xFF666666);
const kBlack500 = Color(0xFF3D3D3D);
const kBlack600 = Color(0xFF282828);
const kBlack700 = Color(0xFF1A1A1A);
const kBlack800 = Color(0xFF111111);
const kBlack900 = Color(0xFF0A0A0A);

/* ============================================================
   Brand tokens — names kept for API compatibility
   ============================================================ */

const kPrimary     = kOrange500; // #FF6B00
const kPrimaryDark = kOrange600; // #E55A00
const kAccent      = kOrange300; // #FFB347
const kAccentDark  = kOrange700; // #CC4500

/// Status tokens remapped to orange family (names kept for compatibility).
const kSuccess = Color(0xFFFF9500); // orange-amber
const kWarning = Color(0xFFFF6B00); // primary orange
const kError   = Color(0xFFCC4500); // deep orange

/// Legacy hue aliases — remapped to orange shades (names kept for compatibility).
const kPink   = kOrange300;
const kPurple = kOrange200;
const kBlue   = kOrange100;
const kOrange = kOrange500;

/// Identity colours for course dots, panels and chips — orange family only.
const kBrandColors = <Color>[kOrange500, kOrange300, kOrange600, kOrange400];

/* ============================================================
   Neutral palette — the only colours that change with dark mode.
   ============================================================ */

class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.card,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.border,
    required this.divider,
    required this.successBg,
    required this.warningBg,
    required this.errorBg,
    required this.snackBarBackground,
    required this.snackBarForeground,
    required this.scrim,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color card;
  final Color textPrimary;
  final Color textBody;
  final Color textSecondary;
  final Color border;
  final Color divider;
  final Color successBg;
  final Color warningBg;
  final Color errorBg;
  final Color snackBarBackground;
  final Color snackBarForeground;

  /// Overlay used by dialogs and bottom sheets.
  final Color scrim;
}

/// Cool white page, near-black type — the light look.
const kLightPalette = AppPalette(
  brightness: Brightness.light,
  background: Color(0xFFF7F7F7),
  surface: Colors.white,
  card: Colors.white,
  textPrimary: Color(0xFF0A0A0A),
  textBody: Color(0xFF282828),
  textSecondary: Color(0xFF666666),
  border: Color(0xFFE8E8E8),
  divider: Color(0xFFF0F0F0),
  successBg: Color(0xFFFFF3E0), // orange-50 tint
  warningBg: Color(0xFFFFE0B2), // orange-100 tint
  errorBg: Color(0xFFFFCC80),   // orange-200 tint
  snackBarBackground: Color(0xFF0A0A0A),
  snackBarForeground: Color(0xFFF7F7F7),
  scrim: Color(0x66000000),
);

/// Pure noir — maximum contrast, electric orange pops hard.
const kDarkPalette = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF0A0A0A),
  surface: Color(0xFF111111),
  card: Color(0xFF1A1A1A),
  textPrimary: Color(0xFFF7F7F7),
  textBody: Color(0xFFE8E8E8),
  textSecondary: Color(0xFF9A9A9A),
  border: Color(0xFF282828),
  divider: Color(0xFF1A1A1A),
  successBg: Color(0xFF282800), // very dark warm
  warningBg: Color(0xFF2B1500), // very dark orange
  errorBg: Color(0xFF1A0A00),   // near-black orange
  snackBarBackground: Color(0xFFF7F7F7),
  snackBarForeground: Color(0xFF0A0A0A),
  scrim: Color(0x99000000),
);

AppPalette _palette = kLightPalette;

/// The palette currently in effect. Read the individual getters below rather
/// than this directly, so widgets stay source-compatible with light mode.
AppPalette get currentPalette => _palette;

/// Swaps the active palette. Called by `ThemeController`; safe to call before
/// the first frame.
void setAppPalette(AppPalette palette) => _palette = palette;

/* ============================================================
   Neutral tokens — getters bound to the active palette.
   ============================================================ */

Color get kBackground      => _palette.background;
Color get kSurface         => _palette.surface;
Color get kCard            => _palette.card;
Color get kTextPrimary     => _palette.textPrimary;
Color get kTextBody        => _palette.textBody;
Color get kTextSecondary   => _palette.textSecondary;
Color get kBorder          => _palette.border;
Color get kDivider         => _palette.divider;
Color get kSuccessBg       => _palette.successBg;
Color get kWarningBg       => _palette.warningBg;
Color get kErrorBg         => _palette.errorBg;

/// True while the dark palette is active — handy for choosing artwork tints.
bool get kIsDark => _palette.brightness == Brightness.dark;

/* ============================================================
   Spacing / radius / elevation scales
   ============================================================ */

/// Spacing scale — use these instead of raw numbers everywhere.
const kSpaceXs  = 6.0;
const kSpaceSm  = 10.0;
const kSpaceMd  = 16.0;
const kSpaceLg  = 24.0;
const kSpaceXl  = 32.0;
const kSpaceXxl = 40.0;

/// Border radius scale.
const kRadiusXs   = 6.0;
const kRadiusSm   = 12.0;
const kRadiusMd   = 20.0;
const kRadiusLg   = 28.0;
const kRadiusXl   = 40.0;
const kRadiusPill = 999.0;

/// Elevation scale (soft shadows only).
const kShadowSm = BoxShadow(
  color: Color(0x0F000000),
  blurRadius: 8,
  offset: Offset(0, 2),
);
const kShadowMd = BoxShadow(
  color: Color(0x14000000),
  blurRadius: 16,
  offset: Offset(0, 6),
);
const kShadowLg = BoxShadow(
  color: Color(0x1E000000),
  blurRadius: 24,
  offset: Offset(0, 10),
);

/* ============================================================
   Themes
   ============================================================ */

/// Builds a [ThemeData] for [palette]. Explicit about its palette so the light
/// and dark objects never bake in whichever one happened to be active.
ThemeData buildAppTheme(AppPalette palette) {
  final isDark = palette.brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimary,
      brightness: palette.brightness,
      surface: palette.surface,
      onSurface: palette.textPrimary,
    ).copyWith(
      primary: kPrimary,
      secondary: kOrange300,
      surface: palette.surface,
      // `background` is deprecated but still read by some Material internals.
      background: palette.background,
      onPrimary: isDark ? kBlack900 : Colors.white,
      onSurface: palette.textPrimary,
      onSecondary: kBlack900,
      outline: palette.border,
      outlineVariant: palette.divider,
    ),
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    cardTheme: CardThemeData(
      elevation: 0,
      color: palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusLg)),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: palette.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: palette.textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: kSpaceMd, vertical: kSpaceMd),
      hintStyle: TextStyle(color: palette.textSecondary, fontSize: 14),
      labelStyle: TextStyle(color: palette.textSecondary),
      prefixIconColor: kPrimary,
      suffixIconColor: palette.textSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide(color: palette.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide(color: palette.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: const BorderSide(color: kError, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: isDark ? kBlack900 : Colors.white,
        disabledForegroundColor: palette.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: kSpaceLg, vertical: kSpaceMd),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceMd, vertical: kSpaceSm),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.snackBarBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
      contentTextStyle: TextStyle(
        color: palette.snackBarForeground,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    ),
    dividerTheme: DividerThemeData(color: palette.divider, space: 2),
    listTileTheme: ListTileThemeData(
      iconColor: palette.textSecondary,
      textColor: palette.textPrimary,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.card,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: palette.textPrimary, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: palette.textPrimary,
      ),
      contentTextStyle: TextStyle(color: palette.textBody, fontSize: 14, height: 1.6),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: palette.textPrimary,
      unselectedLabelColor: palette.textSecondary,
      indicatorColor: kPrimary,
      dividerColor: palette.divider,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kPrimary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isDark ? kBlack900 : Colors.white;
        }
        return palette.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kPrimary;
        return palette.border;
      }),
    ),
    textTheme: TextTheme(
      displayLarge:   TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: palette.textPrimary, height: 1.1),
      displayMedium:  TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: palette.textPrimary, height: 1.15),
      headlineLarge:  TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: palette.textPrimary, height: 1.2),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: palette.textPrimary, height: 1.25),
      headlineSmall:  TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: palette.textPrimary, height: 1.3),
      titleLarge:     TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary, height: 1.4),
      titleMedium:    TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary, height: 1.4),
      titleSmall:     TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: palette.textPrimary, height: 1.5),
      bodyLarge:      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.textBody,    height: 1.6),
      bodyMedium:     TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textBody,    height: 1.6),
      bodySmall:      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.textBody,    height: 1.6),
      labelLarge:     TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary, height: 1.4),
      labelMedium:    TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textSecondary, height: 1.5),
      labelSmall:     TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: palette.textSecondary, height: 1.5),
    ),
  );
}

/// Light theme.
final ThemeData appTheme = buildAppTheme(kLightPalette);

/// Dark theme.
final ThemeData darkAppTheme = buildAppTheme(kDarkPalette);

/* ============================================================
   Gradients & helpers
   ============================================================ */

/// Signature hero gradient — electric orange to deep orange.
const candyGradient = LinearGradient(
  colors: [kOrange500, kOrange700],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Flame gradient — warm orange sweep, top-left to bottom-right.
const flamGradient = LinearGradient(
  colors: [kOrange400, kOrange600],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Noir gradient — deep black to absolute black.
const noirGradient = LinearGradient(
  colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Ash gradient — crisp white to near-white, for light surfaces.
const ashGradient = LinearGradient(
  colors: [Color(0xFFFFFFFF), Color(0xFFF0F0F0)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Playful gradient used on hero cards, floating chips, and active nav tabs.
LinearGradient livelyGradient(Color start, Color end) => LinearGradient(
  colors: [start, end],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Soft tint for subtle background chips (per accent colour).
tintOf(Color color, [double opacity = 0.10]) => color.withValues(alpha: opacity);

/// Darkens [color] toward black by [amount] (0..1).
Color shadeOf(Color color, [double amount = 0.15]) => Color.lerp(color, Colors.black, amount)!;

/// Per-tab accent colours — orange family only.
const kTabColors = <Color>[
  kOrange500, // Dashboard
  kOrange400, // Courses
  kOrange300, // Calendar
  kOrange600, // Chat
  kOrange700, // Integrity
  kOrange500, // Students
  kOrange400, // Departments
  kOrange300, // Attendance
  kOrange600, // Notes
];

/// Helper: read text styles cleanly.
extension TextScale on BuildContext {
  TextStyle get h1        => Theme.of(this).textTheme.displayMedium!;
  TextStyle get h2        => Theme.of(this).textTheme.headlineLarge!;
  TextStyle get h3        => Theme.of(this).textTheme.headlineMedium!;
  TextStyle get h4        => Theme.of(this).textTheme.headlineSmall!;
  TextStyle get h5        => Theme.of(this).textTheme.titleLarge!;
  TextStyle get subtitle1 => Theme.of(this).textTheme.titleMedium!;
  TextStyle get subtitle2 => Theme.of(this).textTheme.titleSmall!;
  TextStyle get body1     => Theme.of(this).textTheme.bodyLarge!;
  TextStyle get body2     => Theme.of(this).textTheme.bodyMedium!;
  TextStyle get caption   => Theme.of(this).textTheme.labelMedium!;
  TextStyle get overline  => Theme.of(this).textTheme.labelSmall!;
}

/// Helper: card shadow. Deep black in dark mode, orange-tinted in light mode.
BoxShadow cardShadow(Color color) => BoxShadow(
  color: kIsDark ? Colors.black.withValues(alpha: 0.55) : color.withValues(alpha: 0.14),
  blurRadius: 20,
  offset: const Offset(0, 8),
);

/// Orange glow shadow for selected / active elements.
BoxShadow flameShadow([double intensity = 1.0]) => BoxShadow(
  color: kPrimary.withValues(alpha: 0.35 * intensity),
  blurRadius: 20 * intensity,
  spreadRadius: 0,
  offset: Offset(0, 6 * intensity),
);

/// Helper: icon bubble gradient decoration.
Decoration iconBubble(Color color) => BoxDecoration(
  gradient: livelyGradient(color, shadeOf(color, 0.15)),
  borderRadius: BorderRadius.circular(kRadiusMd),
  boxShadow: [
    BoxShadow(
      color: color.withValues(alpha: 0.35),
      blurRadius: 12,
      offset: const Offset(0, 5),
    ),
  ],
);

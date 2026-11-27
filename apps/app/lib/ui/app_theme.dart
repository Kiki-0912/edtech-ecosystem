import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

const String kFontFamily = 'Inter';

TextTheme _textTheme(AppColors c) {
  TextStyle s(double size, FontWeight weight, Color color,
          {double height = 1.4, double spacing = 0}) =>
      TextStyle(
        fontFamily: kFontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );

  return TextTheme(
    displaySmall:
        s(32, FontWeight.w700, c.textPrimary, height: 1.2, spacing: -0.5),
    headlineMedium:
        s(26, FontWeight.w700, c.textPrimary, height: 1.25, spacing: -0.4),
    headlineSmall:
        s(22, FontWeight.w700, c.textPrimary, height: 1.3, spacing: -0.3),
    titleLarge: s(18, FontWeight.w600, c.textPrimary, height: 1.35),
    titleMedium: s(16, FontWeight.w600, c.textPrimary),
    titleSmall: s(14, FontWeight.w600, c.textPrimary),
    bodyLarge: s(16, FontWeight.w400, c.textPrimary, height: 1.5),
    bodyMedium: s(14, FontWeight.w400, c.textSecondary, height: 1.5),
    bodySmall: s(12, FontWeight.w400, c.textMuted),
    labelLarge: s(14, FontWeight.w600, c.textPrimary),
    labelMedium: s(12, FontWeight.w500, c.textSecondary),
    labelSmall: s(11, FontWeight.w600, c.textMuted, spacing: 0.4),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final text = _textTheme(c);

  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandOrange,
    brightness: brightness,
  ).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accentText,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceContainerHighest: c.surfaceMuted,
    outline: c.border,
    outlineVariant: c.border,
    error: c.danger,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: AppRadius.mdAll,
    borderSide: BorderSide(color: c.border),
  );

  const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
  const buttonPadding =
      EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm);
  const minButton = Size(64, 44);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kFontFamily,
    textTheme: text,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.border,
    extensions: [c],
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: Border(bottom: BorderSide(color: c.border)),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: c.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.surfaceMuted,
        disabledForegroundColor: c.textMuted,
        minimumSize: minButton,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        minimumSize: minButton,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.border),
        minimumSize: minButton,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentText,
        minimumSize: const Size(48, 40),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.textSecondary,
        minimumSize: const Size(44, 44),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
      elevation: 2,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.accent, width: 1.5)),
      errorBorder:
          inputBorder.copyWith(borderSide: BorderSide(color: c.danger)),
      focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.danger, width: 1.5)),
      labelStyle: text.bodyMedium,
      hintStyle: text.bodyMedium?.copyWith(color: c.textMuted),
      prefixIconColor: c.textMuted,
      suffixIconColor: c.textMuted,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.accentSoft,
      side: BorderSide(color: c.border),
      labelStyle: text.labelMedium,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.accentSoft,
        selectedForegroundColor: c.accentText,
        foregroundColor: c.textSecondary,
        side: BorderSide(color: c.border),
        textStyle: text.labelMedium,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentSoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
                color: states.contains(WidgetState.selected)
                    ? c.accentText
                    : c.textMuted,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w500,
              )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.accentText
                : c.textMuted,
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accentSoft,
      selectedIconTheme: IconThemeData(color: c.accentText),
      unselectedIconTheme: IconThemeData(color: c.textMuted),
      selectedLabelTextStyle: text.labelMedium
          ?.copyWith(color: c.accentText, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(color: c.textMuted),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.textSecondary,
      textColor: c.textPrimary,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.border,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: text.bodyMedium?.copyWith(color: c.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: c.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.textPrimary,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.background),
      actionTextColor: c.accent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.accentText,
      unselectedLabelColor: c.textMuted,
      indicatorColor: c.accent,
      labelStyle: text.titleSmall,
      unselectedLabelStyle: text.titleSmall,
      dividerColor: c.border,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.surfaceMuted,
      circularTrackColor: c.surfaceMuted,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textMuted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceMuted),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.textPrimary,
        borderRadius: AppRadius.smAll,
      ),
      textStyle: text.labelMedium?.copyWith(color: c.background),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: c.surface,
      headerForegroundColor: c.textPrimary,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
    ),
  );
}

final ThemeData lightTheme = buildTheme(Brightness.light);
final ThemeData darkTheme = buildTheme(Brightness.dark);

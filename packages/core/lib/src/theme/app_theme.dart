import 'package:flutter/material.dart';

/// Colours shared by both apps. Calm, low-contrast neutrals with one teal accent.
abstract final class AppColors {
  static const teal = Color(0xFF0F6F6F);
  static const tealDark = Color(0xFF0A5555);
  static const tealTint = Color(0xFFE3F1F1);
  static const background = Color(0xFFF5F7F7);
  static const surface = Colors.white;
  static const border = Color(0xFFD3DADA);
  static const text = Color(0xFF1E2B2B);
  static const textMuted = Color(0xFF566666);
  static const error = Color(0xFFA83232);
  static const errorTint = Color(0xFFFBEDED);
  static const success = Color(0xFF2B7A4B);
  static const successTint = Color(0xFFE6F3EA);
  static const warning = Color(0xFF8A5A00);
  static const warningTint = Color(0xFFFFF4DC);
}

/// Corner radius used across the apps (square-ish, office-tool look).
const double kRadius = 3;

/// Font stack for raw data views.
const List<String> kMonospaceFallback = [
  'Menlo',
  'Consolas',
  'Courier New',
  'monospace',
];

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.teal,
    onPrimary: Colors.white,
    primaryContainer: AppColors.tealTint,
    onPrimaryContainer: AppColors.tealDark,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    error: AppColors.error,
    errorContainer: AppColors.errorTint,
    onErrorContainer: AppColors.error,
  );

  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(kRadius)),
  );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  const buttonSize = Size(64, 40);

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(kRadius)),
        borderSide: BorderSide(color: color, width: width),
      );

  const base = TextTheme(
    headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15, height: 1.4),
    bodyMedium: TextStyle(fontSize: 14, height: 1.4),
    bodySmall: TextStyle(fontSize: 13, height: 1.35),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.compact,
    textTheme: base.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      space: 1,
      thickness: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 52,
      shape: Border(bottom: BorderSide(color: AppColors.border)),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadius)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: inputBorder(AppColors.border),
      enabledBorder: inputBorder(AppColors.border),
      focusedBorder: inputBorder(AppColors.teal, 2),
      errorBorder: inputBorder(AppColors.error),
      focusedErrorBorder: inputBorder(AppColors.error, 2),
      labelStyle: const TextStyle(color: AppColors.textMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        padding: buttonPadding,
        minimumSize: buttonSize,
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        padding: buttonPadding,
        minimumSize: buttonSize,
        foregroundColor: AppColors.teal,
        side: const BorderSide(color: AppColors.teal),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        minimumSize: const Size(48, 40),
        foregroundColor: AppColors.teal,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: shape,
      side: const BorderSide(color: AppColors.border),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.tealTint,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.text),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadius)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.teal,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.teal,
      dividerColor: AppColors.border,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadius)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
      side: const BorderSide(color: AppColors.textMuted, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? AppColors.teal : null,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.teal
            : AppColors.border,
      ),
    ),
    dataTableTheme: const DataTableThemeData(
      headingTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
      dataTextStyle: TextStyle(fontSize: 14, color: AppColors.text),
      headingRowColor: WidgetStatePropertyAll(Color(0xFFEDF1F1)),
      dividerThickness: 1,
    ),
  );
}

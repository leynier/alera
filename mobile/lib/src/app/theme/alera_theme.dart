import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

ThemeData buildAleraMobileDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final colorScheme = const ColorScheme.dark().copyWith(
    brightness: Brightness.dark,
    primary: AleraTokens.accent,
    onPrimary: AleraTokens.onAccent,
    primaryContainer: AleraTokens.surfaceElevated,
    onPrimaryContainer: AleraTokens.foreground,
    secondary: AleraTokens.accent,
    onSecondary: AleraTokens.onAccent,
    secondaryContainer: AleraTokens.surfaceElevated,
    onSecondaryContainer: AleraTokens.foreground,
    tertiary: AleraTokens.accent,
    onTertiary: AleraTokens.onAccent,
    tertiaryContainer: AleraTokens.surfaceElevated,
    onTertiaryContainer: AleraTokens.foreground,
    surface: AleraTokens.surface,
    onSurface: AleraTokens.foreground,
    surfaceContainerLowest: AleraTokens.bg,
    surfaceContainerLow: AleraTokens.surface,
    surfaceContainer: AleraTokens.surfaceVariant,
    surfaceContainerHigh: AleraTokens.surfaceElevated,
    surfaceContainerHighest: AleraTokens.surfaceVariant,
    error: AleraTokens.error,
    onError: AleraTokens.onError,
    outline: AleraTokens.border,
    outlineVariant: AleraTokens.borderSubtle,
    onSurfaceVariant: AleraTokens.foregroundMuted,
  );
  final textTheme = base.textTheme
      .apply(fontFamily: AleraTokens.fontFamily)
      .copyWith(
        headlineLarge: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AleraTokens.foreground,
          letterSpacing: -0.5,
        ),
        headlineMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AleraTokens.foreground,
          letterSpacing: -0.3,
        ),
        headlineSmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AleraTokens.foreground,
          letterSpacing: -0.2,
        ),
        titleLarge: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AleraTokens.foreground,
        ),
        titleMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AleraTokens.foreground,
        ),
        titleSmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AleraTokens.foreground,
        ),
        bodyLarge: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AleraTokens.foreground,
        ),
        bodyMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AleraTokens.foreground,
        ),
        bodySmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AleraTokens.foregroundMuted,
        ),
        labelLarge: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AleraTokens.foreground,
        ),
        labelMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AleraTokens.foregroundMuted,
          letterSpacing: 0.5,
        ),
        labelSmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AleraTokens.foregroundMuted,
          letterSpacing: 0.6,
        ),
      );
  final buttonShape = WidgetStateProperty.all<OutlinedBorder>(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    ),
  );
  final buttonSize = WidgetStateProperty.all<Size>(const Size(0, 34));
  return base.copyWith(
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: AleraTokens.bg,
    canvasColor: AleraTokens.bg,
    dividerColor: AleraTokens.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: AleraTokens.surface,
      foregroundColor: AleraTokens.foreground,
      elevation: 0,
      centerTitle: true,
      titleSpacing: 0,
    ),
    cardTheme: CardThemeData(
      color: AleraTokens.surfaceVariant,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AleraTokens.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        borderSide: const BorderSide(color: AleraTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        borderSide: const BorderSide(color: AleraTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        borderSide: const BorderSide(color: AleraTokens.accent),
      ),
      hintStyle: const TextStyle(color: AleraTokens.foregroundMuted),
      labelStyle: textTheme.labelMedium,
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      iconColor: AleraTokens.foregroundMuted,
      textColor: AleraTokens.foreground,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        minimumSize: buttonSize,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        foregroundColor: WidgetStateProperty.all(AleraTokens.foreground),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(shape: buttonShape, minimumSize: buttonSize),
    ),
    dividerTheme: const DividerThemeData(
      color: AleraTokens.border,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AleraTokens.surfaceElevated,
      contentTextStyle: textTheme.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AleraTokens.surfaceElevated,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        side: const BorderSide(color: AleraTokens.border),
      ),
      menuPadding: const EdgeInsets.all(AleraTokens.space12),
      textStyle: textTheme.bodyMedium,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AleraTokens.surfaceElevated,
      foregroundColor: AleraTokens.foreground,
      elevation: 1,
      focusElevation: 1,
      hoverElevation: 1,
      highlightElevation: 1,
      disabledElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        side: const BorderSide(color: AleraTokens.border),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return AleraTokens.onAccent;
        }
        return AleraTokens.foregroundMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return AleraTokens.accent;
        }
        return AleraTokens.surfaceVariant;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return AleraTokens.accent;
        }
        return AleraTokens.border;
      }),
    ),
  );
}

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildAleraDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final colorScheme = const ColorScheme.dark().copyWith(
    brightness: Brightness.dark,
    primary: AleraTokens.accent,
    onPrimary: AleraTokens.onAccent,
    secondary: AleraTokens.accent,
    onSecondary: AleraTokens.onAccent,
    surface: AleraTokens.surface,
    onSurface: AleraTokens.foreground,
    error: AleraTokens.error,
    onError: AleraTokens.onError,
    outline: AleraTokens.border,
    onSurfaceVariant: AleraTokens.foregroundMuted,
  );
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
    headlineLarge: GoogleFonts.inter(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: AleraTokens.foreground,
      letterSpacing: -0.5,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AleraTokens.foreground,
      letterSpacing: -0.3,
    ),
    headlineSmall: GoogleFonts.inter(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AleraTokens.foreground,
      letterSpacing: -0.2,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AleraTokens.foreground,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foreground,
    ),
    titleSmall: GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foreground,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AleraTokens.foreground,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: AleraTokens.foreground,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: AleraTokens.foregroundMuted,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foreground,
    ),
    labelMedium: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foregroundMuted,
      letterSpacing: 0.5,
    ),
    labelSmall: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foregroundMuted,
      letterSpacing: 0.6,
    ),
  );
  final clickableCursor = WidgetStateProperty.resolveWith<MouseCursor>((
    states,
  ) {
    if (states.contains(WidgetState.disabled)) {
      return SystemMouseCursors.basic;
    }
    return SystemMouseCursors.click;
  });
  final buttonShape = WidgetStateProperty.all<OutlinedBorder>(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
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
    ),
    cardTheme: CardThemeData(
      color: AleraTokens.surfaceVariant,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
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
    listTileTheme: ListTileThemeData(
      dense: true,
      iconColor: AleraTokens.foregroundMuted,
      textColor: AleraTokens.foreground,
      mouseCursor: clickableCursor,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickableCursor,
        shape: buttonShape,
        minimumSize: buttonSize,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickableCursor,
        shape: buttonShape,
        foregroundColor: WidgetStateProperty.all(AleraTokens.foreground),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickableCursor,
        shape: buttonShape,
        minimumSize: buttonSize,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(mouseCursor: clickableCursor),
    ),
    dividerTheme: const DividerThemeData(
      color: AleraTokens.border,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AleraTokens.border),
      thickness: WidgetStateProperty.all(4),
      radius: const Radius.circular(2),
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
  );
}

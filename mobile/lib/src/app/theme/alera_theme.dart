import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

ThemeData buildAleraMobileDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final colorScheme = const ColorScheme.dark().copyWith(
    brightness: .dark,
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
          fontWeight: .w600,
          color: AleraTokens.foreground,
          letterSpacing: -0.5,
        ),
        headlineMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 22,
          fontWeight: .w600,
          color: AleraTokens.foreground,
          letterSpacing: -0.3,
        ),
        headlineSmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 18,
          fontWeight: .w600,
          color: AleraTokens.foreground,
          letterSpacing: -0.2,
        ),
        titleLarge: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 16,
          fontWeight: .w600,
          color: AleraTokens.foreground,
        ),
        titleMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 14,
          fontWeight: .w500,
          color: AleraTokens.foreground,
        ),
        titleSmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 13,
          fontWeight: .w500,
          color: AleraTokens.foreground,
        ),
        bodyLarge: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 14,
          fontWeight: .w400,
          color: AleraTokens.foreground,
        ),
        bodyMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 13,
          fontWeight: .w400,
          color: AleraTokens.foreground,
        ),
        bodySmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 12,
          fontWeight: .w400,
          color: AleraTokens.foregroundMuted,
        ),
        labelLarge: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 13,
          fontWeight: .w500,
          color: AleraTokens.foreground,
        ),
        labelMedium: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 11,
          fontWeight: .w500,
          color: AleraTokens.foregroundMuted,
          letterSpacing: 0.5,
        ),
        labelSmall: const TextStyle(
          fontFamily: AleraTokens.fontFamily,
          fontSize: 10,
          fontWeight: .w500,
          color: AleraTokens.foregroundMuted,
          letterSpacing: 0.6,
        ),
      );
  final buttonShape = WidgetStateProperty.all<OutlinedBorder>(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    ),
  );
  final buttonSize = WidgetStateProperty.all<Size>(
    const Size(0, AleraTokens.buttonMinHeight),
  );
  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
    borderRadius: .circular(AleraTokens.radiusMd),
    borderSide: BorderSide(color: color),
  );
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
      // Clips ink splashes to the card radius, so a tappable card needs no
      // radius of its own on its InkWell.
      clipBehavior: .antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AleraTokens.surfaceVariant,
      contentPadding: AleraTokens.inputContentPadding,
      border: inputBorder(AleraTokens.border),
      enabledBorder: inputBorder(AleraTokens.border),
      focusedBorder: inputBorder(AleraTokens.accent),
      errorBorder: inputBorder(AleraTokens.error),
      focusedErrorBorder: inputBorder(AleraTokens.error),
      hintStyle: const TextStyle(color: AleraTokens.foregroundMuted),
      labelStyle: textTheme.labelMedium,
      errorStyle: textTheme.bodySmall?.copyWith(color: AleraTokens.error),
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
          const EdgeInsets.symmetric(
            horizontal: AleraTokens.buttonPaddingHorizontal,
          ),
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
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        iconSize: const WidgetStatePropertyAll<double>(AleraTokens.iconMd),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.disabled)
              ? AleraTokens.foregroundFaint
              : null,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return AleraTokens.surfaceElevated;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return AleraTokens.foreground;
          }
          return AleraTokens.foregroundMuted;
        }),
        iconColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return AleraTokens.foreground;
          }
          return AleraTokens.foregroundMuted;
        }),
        side: WidgetStateProperty.all(
          const BorderSide(color: AleraTokens.border),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      selectedColor: AleraTokens.surfaceElevated,
      disabledColor: Colors.transparent,
      checkmarkColor: AleraTokens.foreground,
      deleteIconColor: AleraTokens.foregroundMuted,
      labelStyle: textTheme.labelLarge,
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? AleraTokens.border
              : AleraTokens.borderSubtle,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return states.contains(WidgetState.disabled)
              ? AleraTokens.foregroundFaint
              : AleraTokens.accent;
        }
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll<Color>(AleraTokens.onAccent),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? AleraTokens.foregroundFaint
              : AleraTokens.foregroundMuted,
          width: AleraTokens.strokeSm,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusXs),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return AleraTokens.foregroundFaint;
        }
        if (states.contains(WidgetState.selected)) {
          return AleraTokens.accent;
        }
        return AleraTokens.foregroundMuted;
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AleraTokens.accent,
      linearTrackColor: AleraTokens.surfaceVariant,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AleraTokens.accent,
      selectionColor: AleraTokens.textSelection,
      selectionHandleColor: AleraTokens.accent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AleraTokens.foreground,
      unselectedLabelColor: AleraTokens.foregroundMuted,
      indicatorColor: AleraTokens.accent,
      dividerColor: AleraTokens.borderSubtle,
      labelStyle: textTheme.titleSmall,
      unselectedLabelStyle: textTheme.titleSmall,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AleraTokens.surface,
      modalBackgroundColor: AleraTokens.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: AleraTokens.barrierDark,
      // showModalBottomSheet reads this flag; the color alone draws nothing.
      showDragHandle: true,
      dragHandleColor: AleraTokens.border,
      clipBehavior: .antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AleraTokens.radiusXl),
        ),
      ),
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
      behavior: .floating,
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

import 'package:alchemist/alchemist.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void runAleraGoldenTests(void Function() body) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final theme = _buildAleraGoldenTheme();
  AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      theme: theme,
      goldenTestTheme: GoldenTestTheme(
        backgroundColor: AleraTokens.bg,
        borderColor: AleraTokens.borderSubtle,
        padding: const EdgeInsets.all(AleraTokens.space16),
        nameTextStyle: theme.textTheme.labelSmall!.copyWith(
          color: AleraTokens.foregroundMuted,
          fontSize: 11,
        ),
      ),
      platformGoldensConfig: const PlatformGoldensConfig(enabled: false),
      ciGoldensConfig: CiGoldensConfig(
        theme: theme,
        obscureText: true,
        renderShadows: false,
      ),
    ),
    run: body,
  );
}

ThemeData _buildAleraGoldenTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = _buildGoldenTextTheme();
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
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    ),
  );
  final buttonSize = WidgetStateProperty.all<Size>(const Size(0, 34));

  return base.copyWith(
    colorScheme: const ColorScheme.dark().copyWith(
      primary: AleraTokens.accent,
      onPrimary: AleraTokens.onAccent,
      secondary: AleraTokens.accent,
      onSecondary: AleraTokens.onAccent,
      surface: AleraTokens.surface,
      onSurface: AleraTokens.foreground,
      surfaceContainerHighest: AleraTokens.surfaceVariant,
      error: AleraTokens.error,
      outline: AleraTokens.border,
      onSurfaceVariant: AleraTokens.foregroundMuted,
    ),
    textTheme: textTheme,
    scaffoldBackgroundColor: AleraTokens.bg,
    canvasColor: AleraTokens.bg,
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
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickableCursor,
        shape: buttonShape,
        minimumSize: buttonSize,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickableCursor,
        shape: buttonShape,
        foregroundColor: WidgetStateProperty.all(AleraTokens.foreground),
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
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickableCursor,
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
  );
}

TextTheme _buildGoldenTextTheme() {
  const family = 'Inter';
  return const TextTheme(
    headlineMedium: TextStyle(
      fontFamily: family,
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AleraTokens.foreground,
    ),
    titleLarge: TextStyle(
      fontFamily: family,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AleraTokens.foreground,
    ),
    titleMedium: TextStyle(
      fontFamily: family,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foreground,
    ),
    titleSmall: TextStyle(
      fontFamily: family,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foreground,
    ),
    bodyMedium: TextStyle(
      fontFamily: family,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: AleraTokens.foreground,
    ),
    bodySmall: TextStyle(
      fontFamily: family,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: AleraTokens.foregroundMuted,
    ),
    labelMedium: TextStyle(
      fontFamily: family,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foregroundMuted,
    ),
    labelSmall: TextStyle(
      fontFamily: family,
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: AleraTokens.foregroundMuted,
    ),
  );
}

class AleraGoldenScenarioSurface extends StatelessWidget {
  const AleraGoldenScenarioSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AleraTokens.space16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

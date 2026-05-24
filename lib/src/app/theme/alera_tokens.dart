import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AleraTokens {
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;

  static const double topBarHeight = 52.0;

  /// Height of the sidebar brand row, the workbench terminal tab strip and
  /// any other "header" band along the top of a major shell column. Keeping
  /// them all at the same height makes the divider line up horizontally.
  static const double sidebarHeaderHeight = 44.0;
  static const double statusBarHeight = 30.0;
  static const double sidebarMinWidth = 220.0;
  static const double sidebarMaxWidth = 460.0;
  static const double sidebarDefaultWidth = 300.0;
  static const double sidebarCollapsedWidth = 52.0;
  static const double activityLogHeight = 160.0;
  static const double imageMaxWidth = 400.0;
  static const double imageMaxHeight = 300.0;

  static const double radiusSm = 4.0;
  static const double radiusMd = 6.0;
  static const double radiusLg = 10.0;
  static const double radiusXl = 12.0;
  static const double radiusPill = 20.0;

  static const Color bg = Color(0xFF101010);
  static const Color surface = Color(0xFF181818);
  static const Color surfaceVariant = Color(0xFF202020);
  static const Color surfaceElevated = Color(0xFF242424);
  static const Color border = Color(0xFF323232);
  static const Color borderSubtle = Color(0xFF272727);
  static const Color accent = Color(0xFFE0E0E0);
  static const Color accentSubtle = Color(0x1AE0E0E0);
  static const Color onAccent = Color(0xFF101010);
  static const Color foreground = Color(0xFFF5F5F5);
  static const Color foregroundMuted = Color(0xFFA1A1A1);
  static const Color foregroundFaint = Color(0xFF606060);
  static const Color success = Color(0xFF22C55E);
  static const Color info = Color(0xFF60A5FA);
  static const Color error = Color(0xFFF87171);
  static const Color onError = Color(0xFF2C0D0D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color shadowSoft = Color(0x14000000);
  static const Color barrierDark = Color(0x8A000000);

  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationMid = Duration(milliseconds: 180);
  static const Duration durationSlow = Duration(milliseconds: 280);

  static TextStyle get monoStyle => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: foregroundMuted,
  );
}

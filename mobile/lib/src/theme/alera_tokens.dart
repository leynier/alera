import 'package:flutter/material.dart';

abstract final class AleraTokens {
  static const Color background = Color(0xFF101010);
  static const Color surface = Color(0xFF181818);
  static const Color surfaceVariant = Color(0xFF202020);
  static const Color surfaceElevated = Color(0xFF242424);
  static const Color border = Color(0xFF323232);
  static const Color borderSubtle = Color(0xFF272727);
  static const Color accent = Color(0xFFE0E0E0);
  static const Color onAccent = Color(0xFF101010);
  static const Color foreground = Color(0xFFF5F5F5);
  static const Color foregroundMuted = Color(0xFFA1A1A1);
  static const Color success = Color(0xFF22C55E);
  static const Color info = Color(0xFF60A5FA);
  static const Color error = Color(0xFFF87171);
  static const Color onError = Color(0xFF2C0D0D);
  static const Color warning = Color(0xFFF59E0B);

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double iconLg = 42;
  static const double emptyIcon = 44;
  static const double terminalPreviewHeight = 280;
  static const double keyColumnWidth = 104;
  static const double radiusSm = 8;
  static const double strokeSm = 2;
  static const double emphasisOverlayAlpha = 0.16;
  static const double squareAspectRatio = 1;
  static const int pairingInputMinLines = 8;
  static const int pairingInputMaxLines = 12;
  static const int previewRowLimit = 3;

  static const EdgeInsets pagePadding = EdgeInsets.all(spaceLg);
  static const EdgeInsets contentPadding = EdgeInsets.all(spaceLg);
}

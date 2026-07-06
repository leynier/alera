import 'package:flutter/material.dart';

abstract final class AleraTokens {
  static const Color background = Color(0xFF090B0F);
  static const Color surface = Color(0xFF111318);
  static const Color surfaceRaised = Color(0xFF1C2028);
  static const Color border = Color(0xFF252A34);
  static const Color primary = Color(0xFF6EE7F9);
  static const Color secondary = Color(0xFFA7F3D0);
  static const Color error = Color(0xFFFCA5A5);
  static const Color foreground = Color(0xFFE5E7EB);

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

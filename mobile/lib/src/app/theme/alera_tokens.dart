import 'package:flutter/material.dart';

abstract final class AleraTokens {
  // Core spacing ladder (matches desktop).
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

  /// Mobile aliases kept for existing call sites.
  static const double spaceXs = space4;
  static const double spaceSm = space8;
  static const double spaceMd = space12;
  static const double spaceLg = space16;
  static const double spaceXl = space24;
  static const double spaceXxl = space32;

  /// Minimum comfortable finger tap target (Material / HIG ~48dp).
  static const double minTapTarget = space48;
  static const double iconSm = space12;

  static const double emptyStateMaxWidth = 520.0;
  static const double conversationMaxWidth = 760.0;
  static const double chatBubbleMaxWidth = 620.0;

  // Control radii match desktop so ported DS widgets look identical.
  static const double radiusSm = 4.0;
  static const double radiusMd = 6.0;
  static const double radiusLg = 10.0;
  static const double radiusXl = 12.0;
  static const double radiusPill = 20.0;

  static const Color bg = Color(0xFF101010);
  static const Color background = bg;
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
  static const Duration durationSpin = Duration(milliseconds: 1200);
  static const Duration codexShimmerCadence = Duration(milliseconds: 80);
  static const Duration codexShimmerCycle = Duration(milliseconds: 1600);
  static const Duration codexElapsedTimeRefreshInterval = Duration(seconds: 1);
  static const double codexPlanPreviewHeight = 248;
  static const double codexPlanPreviewFadeHeight = space48 * 2;
  static const double codexChatFooterMaxHeight =
      codexPlanPreviewHeight + minTapTarget * 4;
  static const double codexComposerRadius = radiusXl;
  static const double codexComposerSingleRowMinWidth = 520;
  static const double codexCatalogRowHeight = minTapTarget + space24;
  static const int codexCatalogVisibleRowCount = 2;
  static const double codexInlineEditorMaxHeight = minTapTarget * 3.5;
  static const int codexRasterPreviewCacheDimension = 2048;
  static const double codexPickerHeightFactor = 0.72;

  static const TextStyle monoStyle = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: foregroundMuted,
  );

  // Mobile-only shell / pairing / terminal metrics.
  static const double iconLg = 42;
  static const double emptyIcon = 44;
  static const double successIcon = 64;
  static const double terminalPreviewHeight = 280;
  static const double terminalRestoreProgressWidth = 180;
  static const double keyColumnWidth = 104;
  static const double strokeSm = 2;
  static const double strokeMd = 3;
  static const double emphasisOverlayAlpha = 0.16;
  static const double scrimAlpha = 0.55;
  static const double squareAspectRatio = 1;
  static const double pairingViewfinderSize = 260;
  static const double tabStripHeight = 56;

  /// Matches desktop terminal/browser tab title max width.
  static const double tabTitleMaxWidthTerminal = 92;

  /// Matches desktop editor-like tab title max width.
  static const double tabTitleMaxWidthEditor = 180;
  static const double accessoryBarHeight = minTapTarget + spaceSm;
  static const int composeBarMaxLines = 4;

  static const Duration keyRepeatInterval = Duration(milliseconds: 90);
  static const int pairingInputMinLines = 6;
  static const int pairingInputMaxLines = 10;
  static const int previewRowLimit = 3;

  static const Duration pairingSuccessAutoClose = Duration(milliseconds: 1200);
  static const Duration expiryTickInterval = Duration(seconds: 1);

  static const String fontFamily = 'Inter';
  static const String monoFontFamily = 'JetBrains Mono';

  static const EdgeInsets pagePadding = EdgeInsets.all(space16);
  static const EdgeInsets contentPadding = EdgeInsets.all(space16);
}

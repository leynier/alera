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
  static const double progressBarHeight = space2;

  /// Mobile aliases kept for existing call sites.
  static const double spaceXs = space4;
  static const double spaceSm = space8;
  static const double spaceMd = space12;
  static const double spaceLg = space16;
  static const double spaceXl = space24;
  static const double spaceXxl = space32;

  /// Minimum comfortable finger tap target (Material / HIG ~48dp).
  static const double minTapTarget = space48;

  /// Leading glyph and dot inside a badge (match desktop).
  static const double iconXs = 10.0;
  static const double statusDotSm = 6.0;
  static const double iconSm = space12;

  /// Status glyphs and tray icons in workspace rows: readable at arm's length
  /// while still fitting the row's 14dp status slot.
  static const double rowMetaIcon = 14.0;
  static const double emptyStateIcon = 28.0;

  /// Phone buttons stay at the Material 40dp height rather than the desktop's
  /// pointer-sized 34dp.
  static const double buttonMinHeight = 40.0;
  static const double buttonPaddingHorizontal = 14.0;
  static const EdgeInsets inputContentPadding = .symmetric(
    horizontal: space12,
    vertical: 10,
  );

  static const double dialogWideWidth = 560.0;
  static const double dialogMaxHeight = 520.0;

  /// File-type glyphs in phone rows: larger than the desktop sidebar's 16.
  static const double iconMd = space20;

  static const double emptyStateMaxWidth = 520.0;
  static const double conversationMaxWidth = 760.0;
  static const double chatBubbleMaxWidth = 620.0;
  static const Size previewPhoneSize = Size(390, 844);

  // Control radii match desktop so ported DS widgets look identical.
  /// Tiny inline elements under ~18dp tall (checkboxes, thin progress bars,
  /// keycaps) where [radiusSm] would read as a blob.
  static const double radiusXs = 4.0;

  /// Chips, badges, tooltips, compact controls, and tab chips.
  static const double radiusSm = 6.0;

  /// Inputs and standard controls.
  static const double radiusMd = 8.0;

  /// Buttons, cards, panels, and grouped containers.
  static const double radiusLg = 8.0;

  /// Dialogs, bottom sheets, and large elevated containers.
  static const double radiusXl = 12.0;

  /// Real pills only: floating pill buttons and toggle tracks.
  static const double radiusPill = 20.0;

  /// Width of the accent rail `AleraActiveRail` draws at the leading edge of
  /// the selected row in a vertical list.
  static const double activeRailWidth = 2.0;

  /// Background alpha for tinted status labels: the tone color at this alpha
  /// behind text in the full tone color.
  static const double statusTintAlpha = 0.14;

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
  // Matches the desktop `done` token so merged pull requests read the same
  // on both surfaces.
  static const Color done = Color(0xFFA78BFA);
  static const Color error = Color(0xFFF87171);
  static const Color onError = Color(0xFF2C0D0D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSubtle = Color(0x1FF59E0B);
  static const Color textSelection = Color(0x59E0E0E0);
  static const Color shadowSoft = Color(0x14000000);
  static const Color barrierDark = Color(0x8A000000);

  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationMid = Duration(milliseconds: 180);
  static const Duration durationSlow = Duration(milliseconds: 280);
  static const Duration durationSpin = Duration(milliseconds: 1200);

  static const double monoFontSize = 12;

  static const TextStyle monoStyle = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: monoFontSize,
    fontWeight: .w400,
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

  /// Hugs a 40dp chip with [spaceXs] above and below. A taller strip only adds
  /// dead space between the app bar title and the tabs.
  static const double tabStripHeight = 48;

  /// Matches desktop terminal/browser tab title max width.
  static const double tabTitleMaxWidthTerminal = 92;

  /// Matches desktop editor-like tab title max width.
  static const double tabTitleMaxWidthEditor = 180;
  static const double accessoryBarHeight = minTapTarget + spaceSm;
  static const int composeBarMaxLines = 4;

  /// Single inset and gap for the terminal input stack. The quick-key strip,
  /// the compose field, and every trailing action share it so the mode toggle
  /// and Send land in one column.
  static const double terminalInputInset = space8;

  /// Width of the fade that reveals more quick keys past the edge of the strip.
  static const double terminalAccessoryFadeWidth = space24;

  static const Duration keyRepeatInterval = Duration(milliseconds: 90);
  static const int pairingInputMinLines = 6;
  static const int pairingInputMaxLines = 10;
  static const int previewRowLimit = 3;

  static const Duration pairingSuccessAutoClose = Duration(milliseconds: 1200);
  static const Duration expiryTickInterval = Duration(seconds: 1);

  static const String fontFamily = 'Inter';
  static const String monoFontFamily = 'JetBrains Mono';

  static const EdgeInsets pagePadding = .all(space16);
  static const EdgeInsets contentPadding = .all(space16);
}

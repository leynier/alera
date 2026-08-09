import 'package:flutter/material.dart';

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

  /// Height of the sidebar brand row, the workbench tab strip and
  /// any other "header" band along the top of a major shell column. Keeping
  /// them all at the same height makes the divider line up horizontally.
  static const double sidebarHeaderHeight = 44.0;
  static const double statusBarHeight = 30.0;
  static const double sidebarMinWidth = 220.0;
  static const double sidebarMaxWidth = 460.0;
  static const double sidebarDefaultWidth = 300.0;
  static const double sidebarCollapsedWidth = 52.0;
  static const double masterDetailDefaultWidth = 240.0;
  static const double masterDetailMinWidth = 180.0;
  static const double masterDetailMaxWidth = 420.0;
  static const double masterDetailMinDetailWidth = 240.0;
  static const double agentCanvasListWidth = 148.0;
  static const double emptyStateMaxWidth = 520.0;
  static const double conversationMaxWidth = 760.0;
  static const double codexConversationMaxWidth = 720.0;
  static const double codexQuestionCardMaxWidth =
      codexConversationMaxWidth - (space16 * 2);
  static const double codexQuestionCardMaxHeight = 340.0;
  // Keeps the inline plan at roughly ten body lines; maximize reveals it all.
  static const double codexPlanPreviewMaxHeight = 200.0;
  static const double codexPlanPreviewFadeHeight = 96.0;
  static const double codexPlanProgressMaxHeight = 280.0;
  static const double codexUserMessageLeftInset = 80.0;
  static const double codexComposerOverlayMaxHeight = 220.0;
  static const double codexRequestMaxHeight = 320.0;
  static const double codexMenuItemHeight = 32.0;
  static const double codexDraftChipHeight = 28.0;
  static const double codexAttachmentRowHeight = 34.0;
  static const double codexAttachmentPreviewSize = 26.0;
  static const double codexAttachmentThumbnailSize = 60.0;
  static const double codexToolPreviewWidth = 180.0;
  static const double codexToolPreviewHeight = 120.0;
  static const double codexStatusDotSize = 7.0;
  static const double imagePreviewMaxScale = 5.0;
  static const double chatBubbleMaxWidth = 620.0;
  static const double activityLogHeight = 160.0;
  static const double imageMaxWidth = 400.0;
  static const double imageMaxHeight = 300.0;
  static const double dialogCompactWidth = 420.0;
  static const double dialogWidth = 440.0;
  static const double dialogWideWidth = 560.0;
  static const double dialogMaxHeight = 520.0;
  // A dialog hosting a terminal is sized by how much output stays legible, not
  // by its text: 720px fits roughly 95 columns at the mono size.
  static const double dialogTerminalWidth = 720.0;
  static const double dialogTerminalHeight = 460.0;
  static const double contextMenuWidth = 220.0;
  static const double wideContentBreakpoint = 760.0;
  static const double desktopPreviewWidth = 980.0;
  static const double automationDialogWidth = 1180.0;
  static const double automationDialogMaxHeight = 760.0;
  static const double automationDialogHeight = 680.0;
  static const double automationInfoLabelWidth = 100.0;
  static const double collapsedSidebarFooterHeight = 72.0;
  static const double dividerExtent = 1.0;
  static const double iconXs = 10.0;
  static const double iconSm = space12;
  static const double iconMd = 14.0;
  static const double iconLg = space16;
  static const double iconXl = 18.0;
  static const double strokeHairline = 1.4;
  static const double strokeThin = 1.5;
  static const double strokeIndicator = 1.6;
  static const double strokeSm = 2.0;

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
  static const Color codexComposerDisabledOverlay = Color(0xCC202020);
  static const Color codexSteeringBorder = Color(0x4DE0E0E0);
  static const Color onAccent = Color(0xFF101010);
  static const Color foreground = Color(0xFFF5F5F5);
  static const Color foregroundMuted = Color(0xFFA1A1A1);
  static const Color foregroundFaint = Color(0xFF606060);
  static const Color success = Color(0xFF22C55E);
  static const Color codexDiffAdditionBackground = Color(0x1F22C55E);
  static const Color info = Color(0xFF60A5FA);
  static const Color error = Color(0xFFF87171);
  static const Color codexDiffDeletionBackground = Color(0x1AF87171);
  static const Color onError = Color(0xFF2C0D0D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color syntaxKeyword = Color(0xFFC792EA);
  static const Color syntaxOperator = Color(0xFF89DDFF);
  static const Color syntaxFunction = Color(0xFF82AAFF);
  static const Color syntaxLiteral = Color(0xFFFFCB6B);
  static const Color syntaxVariable = Color(0xFFFFCC80);
  static const Color shadowSoft = Color(0x14000000);
  static const Color barrierDark = Color(0x8A000000);

  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationMid = Duration(milliseconds: 180);
  static const Duration durationSlow = Duration(milliseconds: 280);
  static const Duration codexPlanFlightDuration = Duration(milliseconds: 360);
  static const Duration codexShimmerDuration = Duration(milliseconds: 1400);
  static const Duration codexShimmerFrameInterval = Duration(milliseconds: 50);

  /// Full-turn period for continuously rotating progress indicators.
  static const Duration durationSpin = Duration(milliseconds: 1200);

  static const double codexSteeringOpacity = 0.6;

  static const TextStyle monoStyle = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: foregroundMuted,
  );
  static const TextStyle monoCompactStyle = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: foregroundMuted,
  );
  static const TextStyle labelFaintStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: foregroundFaint,
  );
  static const TextStyle labelMicroFaintStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: foregroundFaint,
  );
}

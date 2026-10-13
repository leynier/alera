import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Color role of an [AleraAttentionChip] count.
enum AleraAttentionTone {
  /// Something is blocked or failing and waits for the user.
  warning,

  /// Something new to read, but nothing is blocked.
  accent,

  /// Nothing needs attention.
  muted;

  Color get color => switch (this) {
    warning => AleraTokens.warning,
    accent => AleraTokens.accent,
    muted => AleraTokens.foregroundMuted,
  };
}

/// Status-bar chip with an icon and an attention count. The count is capped
/// at `999+`; the [tooltip] carries the full meaning.
class const AleraAttentionChip({
  super.key,
  required final IconData icon,
  required final int count,
  required final String tooltip,
  final AleraAttentionTone tone = AleraAttentionTone.muted,
  final VoidCallback? onPressed,
}) extends StatelessWidget {
  /// The count as the chip and rail badges print it.
  static String formatCount(int count) => count > 999 ? '999+' : '$count';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        // Every clickable chip in the status bar uses the hand cursor; the
        // InkWell default stays an arrow off the web.
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: Semantics(
            button: true,
            label: tooltip,
            excludeSemantics: true,
            child: Container(
              height: AleraTokens.statusBarHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
              ),
              child: Row(
                mainAxisSize: .min,
                children: <Widget>[
                  Icon(
                    icon,
                    size: AleraTokens.iconStatusBar,
                    color: tone.color,
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  Text(
                    formatCount(count),
                    style: AleraTokens.statusBarTextStyle.copyWith(
                      color: tone.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

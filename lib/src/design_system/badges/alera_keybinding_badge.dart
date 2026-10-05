import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Keycap-styled label for a formatted keyboard chord such as `Ctrl+Shift+P`
/// or `⌘K`. Callers format the chord for the current platform; the badge only
/// draws it, so it stays previewable without a keybinding resolver.
class const AleraKeybindingBadge({super.key, required final String label})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusXs),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: AleraTokens.monoCompactStyle.copyWith(
          color: AleraTokens.foreground,
          fontWeight: .w500,
        ),
      ),
    );
  }
}

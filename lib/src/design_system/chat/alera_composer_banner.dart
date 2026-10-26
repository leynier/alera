import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_keybinding_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// A strip across the top of a composer that names the mode the composer is
/// in, such as editing a queued message, and the way back out of it. Sits in
/// `AleraComposer.header`, so the field below keeps the caret.
class const AleraComposerBanner({
  super.key,
  required final String title,
  final IconData icon = AleraIcons.edit,

  /// Sentence-case context after the title, such as what stays unchanged.
  final String? detail,
  final VoidCallback? onCancel,
  final String cancelLabel = 'Cancel',

  /// The formatted key that also cancels, drawn as a keycap beside Cancel.
  final String? cancelShortcutLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space4,
        AleraTokens.space4,
        AleraTokens.space4,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: AleraTokens.iconMd, color: AleraTokens.accent),
          const SizedBox(width: AleraTokens.space8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              detail ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          if (onCancel != null && cancelShortcutLabel != null) ...<Widget>[
            AleraKeybindingBadge(label: cancelShortcutLabel!),
            const SizedBox(width: AleraTokens.space4),
          ],
          if (onCancel != null)
            TextButton(
              key: const ValueKey<String>('composer-banner-cancel'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AleraTokens.iconButtonSm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AleraTokens.foregroundMuted,
                textStyle: theme.textTheme.labelSmall,
              ),
              onPressed: onCancel,
              child: Text(cancelLabel),
            ),
        ],
      ),
    );
  }
}

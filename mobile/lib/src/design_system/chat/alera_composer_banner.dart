import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// A strip across the top of a composer that names the mode the composer is
/// in, such as editing a queued message, and the way back out of it. The
/// desktop counterpart also draws the key that cancels; a phone has none.
class const AleraComposerBanner({
  super.key,
  required final String title,
  final IconData icon = AleraIcons.edit,

  /// Sentence-case context after the title, such as what stays unchanged.
  final String? detail,
  final VoidCallback? onCancel,
  final String cancelLabel = 'Cancel',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: AleraTokens.space16, color: AleraTokens.accent),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
                children: <InlineSpan>[
                  if (detail case final String detail)
                    TextSpan(
                      text: '  $detail',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onCancel != null)
            TextButton(
              key: const ValueKey<String>('composer-banner-cancel'),
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  AleraTokens.minTapTarget,
                  AleraTokens.minTapTarget,
                ),
                foregroundColor: AleraTokens.foregroundMuted,
              ),
              onPressed: onCancel,
              child: Text(cancelLabel),
            ),
        ],
      ),
    );
  }
}

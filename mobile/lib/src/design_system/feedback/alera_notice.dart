import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Compact helper callout for a constraint or read-only state.
class const AleraNotice({
  super.key,
  required final String message,
  final IconData? icon,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        child: Row(
          crossAxisAlignment: action == null ? .start : .center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: AleraTokens.foregroundMuted),
              const SizedBox(width: AleraTokens.space8),
            ],
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space8),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Centered, low-emphasis placeholder shown when a list or search yields no
/// results. Optionally renders a leading [icon] and a trailing [action].
class const AleraEmptyState({
  super.key,
  final String? title,
  required final String message,
  final IconData? icon,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.emptyStateMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 28, color: AleraTokens.foregroundFaint),
                const SizedBox(height: AleraTokens.space12),
              ],
              if (title case final title? when title.trim().isNotEmpty) ...[
                Text(
                  title,
                  textAlign: .center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AleraTokens.space8),
              ],
              Text(
                message,
                textAlign: .center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

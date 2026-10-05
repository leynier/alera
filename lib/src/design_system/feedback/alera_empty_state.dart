import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Centered, low-emphasis placeholder shown when a list or search yields no
/// results. Optionally renders a leading [icon] and a trailing [action], which
/// may be any widget (a button, or a list of choices).
///
/// With [loading] it shows a small spinner in the icon slot instead, so a
/// pending list and its empty result share one layout.
class const AleraEmptyState({
  super.key,
  final String? title,
  required final String message,
  final IconData? icon,
  final Widget? action,
  final bool loading = false,
  final EdgeInsetsGeometry padding = const EdgeInsets.all(AleraTokens.space24),
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
          padding: padding,
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              if (loading) ...<Widget>[
                const SizedBox.square(
                  dimension: AleraTokens.iconLg,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(height: AleraTokens.space12),
              ] else if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: AleraTokens.iconEmptyState,
                  color: AleraTokens.foregroundFaint,
                ),
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

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Centered, low-emphasis placeholder shown when a list or search yields no
/// results, or when a load failed. Optionally renders a leading [icon], a
/// selectable [detail] (an error message worth copying into a report), and a
/// trailing [action].
class const AleraEmptyState({
  super.key,
  final String? title,
  required final String message,
  final String? detail,
  final IconData? icon,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrolls when a long detail outgrows the space it was given rather than
    // overflowing; short content still sits centered.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AleraTokens.space24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AleraTokens.emptyStateMaxWidth,
          ),
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: AleraTokens.emptyStateIcon,
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
              if (detail case final detail? when detail.trim().isNotEmpty) ...[
                const SizedBox(height: AleraTokens.space8),
                SelectableText(
                  detail,
                  textAlign: .center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
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

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Centered, low-emphasis placeholder shown when a list or search yields no
/// results. Optionally renders a leading [icon] and a trailing [action].
class AleraEmptyState extends StatelessWidget {
  const AleraEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.action,
  });

  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 28, color: AleraTokens.foregroundFaint),
            const SizedBox(height: AleraTokens.space12),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
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
    );
  }
}

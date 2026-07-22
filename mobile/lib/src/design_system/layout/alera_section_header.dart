import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Uppercase, low-emphasis label that introduces a group of rows.
class AleraSectionHeader extends StatelessWidget {
  const AleraSectionHeader({
    super.key,
    required this.label,
    this.leadingIcon,
    this.trailing,
    this.padding,
  });

  final String label;
  final IconData? leadingIcon;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          padding ??
          const EdgeInsets.only(
            left: AleraTokens.space12,
            right: AleraTokens.space8,
            top: AleraTokens.space8,
            bottom: AleraTokens.space4,
          ),
      child: Row(
        children: <Widget>[
          if (leadingIcon != null) ...<Widget>[
            Icon(leadingIcon, size: 12, color: AleraTokens.foregroundFaint),
            const SizedBox(width: AleraTokens.space6),
          ],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

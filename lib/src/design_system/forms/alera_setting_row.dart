import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// A labeled settings row: title (+ optional description) on the left and a
/// fixed-width control on the right. Pair it with any control widget
/// (switch, [AleraNumberField], dropdown, color field, ...) as [child].
class AleraSettingRow extends StatelessWidget {
  const AleraSettingRow({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.controlWidth = 220,
  });

  final String title;
  final Widget child;
  final String? description;
  final double controlWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (description != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space4),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space16),
          SizedBox(width: controlWidth, child: child),
        ],
      ),
    );
  }
}

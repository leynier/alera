import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// One fact in a detail view: a muted [label] in a fixed-width column
/// ([AleraTokens.keyValueLabelWidth]) and a selectable [value] beside it, so a
/// stack of rows lines its values up. An optional leading [icon] precedes the
/// label and an optional [trailing] widget (a badge, a copy or open action)
/// follows the value. [monospace] renders identifiers and paths in the mono
/// style.
class const AleraKeyValueRow({
  super.key,
  required final String label,
  required final String value,
  final IconData? icon,
  final Widget? trailing,
  final bool monospace = false,
  final double labelWidth = AleraTokens.keyValueLabelWidth,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = monospace
        ? AleraTokens.monoStyle.copyWith(color: AleraTokens.foreground)
        : theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundFaint,
                  ),
                  const SizedBox(width: AleraTokens.space6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(child: SelectableText(value, style: valueStyle)),
          if (trailing case final trailing?) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            trailing,
          ],
        ],
      ),
    );
  }
}

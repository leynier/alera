import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

class const MobileSectionHeader({
  super.key,
  required final String label,
  required final int count,
  required final bool collapsed,
  required final VoidCallback onToggle,
  final IconData? icon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expanded = !collapsed;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space2,
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: .circular(AleraTokens.radiusLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space8,
            ),
            decoration: BoxDecoration(
              color: AleraTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            alignment: Alignment.center,
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 14, color: AleraTokens.foregroundMuted),
                  const SizedBox(width: AleraTokens.space6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: .w600,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Text(
                  count.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                    fontWeight: .w500,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  expanded ? AleraIcons.chevronUp : AleraIcons.chevronDown,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

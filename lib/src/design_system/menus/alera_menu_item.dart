import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Row used inside picker/autocomplete popovers. Renders three states:
/// [active] (keyboard-highlighted), [selected] (current value, shows a check)
/// and idle. An optional [leading] widget replaces the default check slot, and
/// an optional [subtitle] renders a secondary line under the label (used by
/// pickers that surface a path or hint).
class const AleraMenuItem({
  super.key,
  required final String label,
  required final bool selected,
  required final VoidCallback onTap,
  final bool active = false,
  final VoidCallback? onHover,
  final Widget? leading,
  final String? subtitle,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: !enabled
          ? AleraTokens.foregroundFaint
          : selected
          ? AleraTokens.foreground
          : AleraTokens.foregroundMuted,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(),
      child: Material(
        color: active && enabled
            ? AleraTokens.surfaceElevated
            : selected
            ? AleraTokens.accentSubtle
            : Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            child: Row(
              crossAxisAlignment: hasSubtitle
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 18,
                  child:
                      leading ??
                      (selected
                          ? const Icon(AleraIcons.check, size: 14)
                          : const SizedBox.shrink()),
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: hasSubtitle
                      ? Column(
                          crossAxisAlignment: .start,
                          children: <Widget>[
                            Text(
                              label,
                              overflow: .ellipsis,
                              maxLines: 1,
                              style: labelStyle,
                            ),
                            const SizedBox(height: AleraTokens.space2),
                            Text(
                              subtitle!,
                              overflow: .ellipsis,
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AleraTokens.foregroundFaint,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          label,
                          overflow: .ellipsis,
                          maxLines: 1,
                          style: labelStyle,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

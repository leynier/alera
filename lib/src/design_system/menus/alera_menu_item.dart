import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Row used inside picker/autocomplete popovers. Renders three states:
/// [active] (keyboard-highlighted), [selected] (current value, shows a check)
/// and idle. An optional [leading] widget replaces the default check slot.
class AleraMenuItem extends StatelessWidget {
  const AleraMenuItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.active = false,
    this.onHover,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool active;
  final VoidCallback? onHover;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(),
      child: Material(
        color: active
            ? AleraTokens.surfaceElevated
            : selected
            ? AleraTokens.accentSubtle
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 18,
                  child:
                      leading ??
                      (selected
                          ? const Icon(Icons.check, size: 14)
                          : const SizedBox.shrink()),
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
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

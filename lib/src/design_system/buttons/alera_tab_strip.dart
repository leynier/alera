import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';

/// One tab of an [AleraTabStrip]. [badge] is a short count such as `6` or
/// `4/9` drawn muted after the label.
class const AleraTabStripItem<T>({
  required final T value,
  required final String label,
  final String? badge,
});

/// Underlined tabs that switch between views of one page. The selected tab
/// draws an accent line over the strip's bottom border; every tab is keyboard
/// reachable with Tab and activates on Enter or Space.
class const AleraTabStrip<T>({
  super.key,
  required final List<AleraTabStripItem<T>> items,
  required final T selected,
  required final ValueChanged<T> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: FocusTraversalGroup(
        child: AleraHorizontalScrollView(
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              for (final item in items)
                _AleraTab<T>(
                  item: item,
                  selected: item.value == selected,
                  onTap: () => onSelected(item.value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _AleraTab<T>({
  required final AleraTabStripItem<T> item,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final badge = item.badge;
    return Semantics(
      key: ValueKey<String>('aleraTab:${item.label}'),
      container: true,
      button: true,
      selected: selected,
      child: Container(
        padding: const EdgeInsets.only(
          left: AleraTokens.space2,
          right: AleraTokens.space2,
          bottom: AleraTokens.space4,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AleraTokens.accent : Colors.transparent,
              width: AleraTokens.strokeSm,
            ),
          ),
        ),
        child: HoverContainer(
          onTap: onTap,
          borderRadius: AleraTokens.radiusSm,
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space6,
          ),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                style: style?.copyWith(
                  fontWeight: .w500,
                  color: selected
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundMuted,
                ),
              ),
              if (badge != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                Text(
                  badge,
                  maxLines: 1,
                  softWrap: false,
                  style: style?.copyWith(
                    color: selected
                        ? AleraTokens.foregroundMuted
                        : AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

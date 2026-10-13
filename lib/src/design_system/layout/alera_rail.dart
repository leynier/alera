import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_attention_chip.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';

/// One destination of an [AleraRail]. A zero [count] shows no badge.
class const AleraRailItem({
  required final IconData icon,
  required final String label,
  final int count = 0,
  final AleraBadgeTone tone = AleraBadgeTone.neutral,
});

/// Vertical section rail at the leading edge of a page. Items are keyboard
/// reachable with Tab and activate on Enter or Space. [compact] drops the
/// labels for narrow windows; the rail itself never collapses.
class const AleraRail({
  super.key,
  required final List<AleraRailItem> items,
  required final int selectedIndex,
  required final ValueChanged<int> onSelected,
  final bool compact = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: SizedBox(
        width: compact ? AleraTokens.railCompactWidth : AleraTokens.railWidth,
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            for (final (index, item) in items.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.space4),
                child: _AleraRailButton(
                  item: item,
                  selected: index == selectedIndex,
                  compact: compact,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class const _AleraRailButton({
  required final AleraRailItem item,
  required final bool selected,
  required final bool compact,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AleraTokens.foreground
        : AleraTokens.foregroundMuted;
    final count = item.count;
    final semantics = count > 0 ? '${item.label}, $count' : item.label;
    final badge = count > 0
        ? AleraBadge(
            label: AleraAttentionChip.formatCount(count),
            tone: item.tone,
          )
        : null;
    Widget content = Column(
      mainAxisSize: .min,
      children: <Widget>[
        Icon(item.icon, size: AleraTokens.iconLg, color: foreground),
        if (!compact) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            item.label,
            maxLines: 1,
            overflow: .ellipsis,
            textAlign: .center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: foreground),
          ),
        ],
        if (badge != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          badge,
        ],
      ],
    );
    if (compact) {
      content = Tooltip(message: item.label, child: content);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      onTap: onTap,
      excludeSemantics: true,
      child: AleraActiveRail(
        active: selected,
        child: HoverContainer(
          onTap: onTap,
          baseColor: selected
              ? AleraActiveRail.selectedColor
              : Colors.transparent,
          borderRadius: AleraTokens.radiusSm,
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space4,
            vertical: AleraTokens.space8,
          ),
          child: content,
        ),
      ),
    );
  }
}

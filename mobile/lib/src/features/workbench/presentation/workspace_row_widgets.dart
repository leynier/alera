import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:flutter/material.dart';

const double _treeIndentStep = 16;

class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({
    super.key,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.icon,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.spaceLg,
          vertical: AleraTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: AleraTokens.spaceLg,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AleraTokens.spaceSm),
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: AleraTokens.spaceLg,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AleraTokens.spaceSm),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              count.toString(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileWorkspaceListRow extends StatelessWidget {
  const MobileWorkspaceListRow({
    super.key,
    required this.row,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleChildren,
  });

  final MobileWorkspaceEntryRow row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleChildren;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = row.entry;
    final workspace = entry.workspace;
    final subtitle = workspace.branch ?? workspace.path;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.only(
          left:
              AleraTokens.spaceLg +
              (row.isPinnedCopy ? 0 : entry.depth) * _treeIndentStep,
          right: AleraTokens.spaceSm,
          top: AleraTokens.spaceSm,
          bottom: AleraTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              workspace.isMain
                  ? Icons.home_outlined
                  : Icons.account_tree_outlined,
              size: AleraTokens.spaceXl,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AleraTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          workspace.name,
                          style: theme.textTheme.bodyLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (workspace.isPinned && !row.isPinnedCopy) ...<Widget>[
                        const SizedBox(width: AleraTokens.spaceSm),
                        Icon(
                          Icons.push_pin,
                          size: AleraTokens.spaceMd,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AleraTokens.spaceXs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: workspace.branch != null
                          ? AleraTokens.monoFontFamily
                          : null,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!row.isPinnedCopy && entry.hasVisibleChildren)
              IconButton(
                tooltip: entry.childrenCollapsed
                    ? 'Expand Children'
                    : 'Collapse Children',
                onPressed: onToggleChildren,
                icon: entry.childrenCollapsed
                    ? Badge.count(
                        count: entry.visibleChildCount,
                        child: const Icon(Icons.chevron_right),
                      )
                    : const Icon(Icons.expand_more),
              ),
          ],
        ),
      ),
    );
  }
}

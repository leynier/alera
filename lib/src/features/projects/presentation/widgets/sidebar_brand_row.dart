import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class SidebarBrandRow extends StatelessWidget {
  const SidebarBrandRow({
    super.key,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggle = IconButton(
      tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      onPressed: onToggleCollapsed,
      icon: Icon(
        collapsed ? Icons.view_sidebar : Icons.view_sidebar_outlined,
        size: 16,
        color: AleraTokens.foregroundMuted,
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
    if (collapsed) {
      return SizedBox(
        height: 48,
        child: Center(child: toggle),
      );
    }
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Alera',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          toggle,
        ],
      ),
    );
  }
}

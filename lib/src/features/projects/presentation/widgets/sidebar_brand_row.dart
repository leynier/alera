import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class SidebarBrandRow extends StatelessWidget {
  const SidebarBrandRow({
    super.key,
    required this.collapsed,
    required this.onToggleCollapsed,
    this.onAddProject,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onAddProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggle = _HeaderIconButton(
      tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      onPressed: onToggleCollapsed,
      icon: collapsed ? Icons.view_sidebar : Icons.view_sidebar_outlined,
    );
    if (collapsed) {
      return SizedBox(
        height: AleraTokens.topBarHeight,
        child: Center(child: toggle),
      );
    }
    return Container(
      height: AleraTokens.topBarHeight,
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
          if (onAddProject != null) ...<Widget>[
            _HeaderIconButton(
              tooltip: 'Add project',
              onPressed: onAddProject!,
              icon: Icons.create_new_folder_outlined,
            ),
            const SizedBox(width: AleraTokens.space4),
          ],
          toggle,
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: AleraTokens.foregroundMuted),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
      ),
    );
  }
}

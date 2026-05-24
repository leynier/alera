import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_icon_button.dart';
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

  /// Optional add-project handler. The workbench sidebar moves this action to
  /// the footer, but the chat-project sidebar still wires it here.
  final VoidCallback? onAddProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggle = SidebarIconButton(
      tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      onPressed: onToggleCollapsed,
      icon: collapsed ? Icons.view_sidebar : Icons.view_sidebar_outlined,
    );
    if (collapsed) {
      return SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: Center(child: toggle),
      );
    }
    return Container(
      height: AleraTokens.sidebarHeaderHeight,
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
            SidebarIconButton(
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

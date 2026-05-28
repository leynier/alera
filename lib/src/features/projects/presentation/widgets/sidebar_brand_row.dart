import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
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

  /// Optional add-project handler. The expanded workbench sidebar moves this
  /// action to the footer, while older callers can still wire it here.
  final VoidCallback? onAddProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggle = AleraIconButton(
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
              kAleraAppName,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onAddProject != null) ...<Widget>[
            AleraIconButton(
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

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
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
      tooltip: collapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
      onPressed: onToggleCollapsed,
      icon: collapsed ? AleraIcons.sidebarToggle : AleraIcons.sidebarToggle,
    );
    if (collapsed) {
      return SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: Align(alignment: Alignment.centerRight, child: toggle),
      );
    }
    return Container(
      height: AleraTokens.sidebarHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Image.asset(
            'assets/logo/alera-logo-white.png',
            width: AleraTokens.space16,
            height: AleraTokens.space16,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: AleraTokens.space8),
          // The logo leaves the name less room, so it yields first when the
          // sidebar is dragged toward its minimum width.
          Flexible(
            child: Text(
              kAleraAppName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          const AleraAppMenuButton(),
          const Spacer(),
          if (onAddProject != null) ...<Widget>[
            AleraIconButton(
              tooltip: 'Add Project',
              onPressed: onAddProject!,
              icon: AleraIcons.newFolder,
            ),
            const SizedBox(width: AleraTokens.space4),
          ],
          toggle,
        ],
      ),
    );
  }
}

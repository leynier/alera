import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workbench_view_options_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sub-toolbar that sits below the sidebar search and exposes view options,
/// the collapse-all toggle and the create-workspace shortcut.
class const WorkbenchSidebarToolbar({super.key, required this.onAddWorkspace})
    extends ConsumerWidget {
  /// Invoked when the user wants to add a workspace. Receives `null` when no
  /// project is currently active so the caller can show a picker; otherwise
  /// the caller is expected to create a workspace under the active project.
  final VoidCallback onAddWorkspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workbenchControllerProvider);
    final controller = ref.read(workbenchControllerProvider.notifier);
    final theme = Theme.of(context);
    final prefs = state.viewPrefs;
    final count = countVisibleWorkspaces(state);

    final collapseTargets = visibleSidebarCollapseTargets(state);
    final allCollapsed = collapseTargets.isCollapsed(prefs);
    final canCollapse = !collapseTargets.isEmpty;
    final hasGitProjects = state.projects.any(
      (project) => project.supportsLinkedWorkspaces,
    );

    final title = prefs.groupBy == WorkbenchGroupBy.project
        ? 'Projects'
        : prefs.groupBy == WorkbenchGroupBy.section
        ? 'Sections'
        : 'Workspaces';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: .w600,
            ),
          ),
          const SizedBox(width: AleraTokens.space6),
          Text(
            count.toString(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundFaint,
              fontWeight: .w500,
            ),
          ),
          const Spacer(),
          AleraIconButton(
            tooltip: 'Go Back',
            onPressed: controller.canGoBack
                ? () => unawaited(controller.goBack())
                : null,
            icon: AleraIcons.back,
          ),
          AleraIconButton(
            tooltip: 'Go Forward',
            onPressed: controller.canGoForward
                ? () => unawaited(controller.goForward())
                : null,
            icon: AleraIcons.forward,
          ),
          const SizedBox(width: AleraTokens.space2),
          const WorkbenchViewOptionsButton(),
          const SizedBox(width: AleraTokens.space2),
          AleraIconButton(
            tooltip: allCollapsed ? 'Expand All' : 'Collapse All',
            onPressed: canCollapse ? controller.toggleCollapseAll : () {},
            icon: allCollapsed ? AleraIcons.expandAll : AleraIcons.collapseAll,
          ),
          const SizedBox(width: AleraTokens.space2),
          AleraIconButton(
            tooltip: hasGitProjects
                ? 'New Workspace'
                : 'Add a Git Project First',
            onPressed: hasGitProjects ? onAddWorkspace : () {},
            icon: AleraIcons.add,
          ),
        ],
      ),
    );
  }
}

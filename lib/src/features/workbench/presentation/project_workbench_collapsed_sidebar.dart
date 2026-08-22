part of 'project_workbench_sidebar.dart';

class _CollapsedSidebar extends StatelessWidget {
  const _CollapsedSidebar({
    required this.state,
    required this.controller,
    required this.onAddProject,
    required this.onOpenSettings,
    required this.onOpenAutomations,
  });

  final WorkbenchState state;
  final WorkbenchController controller;
  final VoidCallback onAddProject;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAutomations;

  @override
  Widget build(BuildContext context) {
    final workspaceCounts = <String, int>{
      for (final project in state.projects)
        project.id: state.workspacesFor(project.id).length,
    };
    return SizedBox(
      width: AleraTokens.sidebarCollapsedWidth,
      child: Container(
        decoration: const BoxDecoration(
          color: AleraTokens.surfaceVariant,
          border: Border(right: BorderSide(color: AleraTokens.borderSubtle)),
        ),
        child: Column(
          children: <Widget>[
            SidebarBrandRow(
              collapsed: true,
              onToggleCollapsed: () =>
                  controller.setCollapsed(!state.collapsed),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: SidebarCollapsedRail(
                projects: state.projects,
                activeProjectId: state.activeProjectId,
                workspaceCountByProject: workspaceCounts,
                onSelectProject: (project) {
                  controller.setCollapsed(false);
                  unawaited(controller.activateProject(project));
                },
                onAddProject: onAddProject,
              ),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            _CollapsedSidebarFooter(
              onOpenSettings: onOpenSettings,
              onOpenAutomations: onOpenAutomations,
            ),
          ],
        ),
      ),
    );
  }
}

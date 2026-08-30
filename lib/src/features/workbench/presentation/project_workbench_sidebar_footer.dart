part of 'project_workbench_sidebar.dart';

class const _EmptyProjectsView({required final VoidCallback onAddProject})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      icon: AleraIcons.folder,
      title: 'No projects yet',
      message: 'Add a git repository to create workspaces with terminal tabs.',
      action: FilledButton.icon(
        onPressed: onAddProject,
        icon: const Icon(AleraIcons.add, size: 16),
        label: const Text('Add Your First Project'),
      ),
    );
  }
}

class const _SidebarFooter({
  required final VoidCallback onAddProject,
  required final VoidCallback onOpenSettings,
  required final VoidCallback onOpenAutomations,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AleraTokens.surface),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onAddProject,
                icon: const Icon(AleraIcons.newFolder),
                label: const Text('Add Project'),
              ),
              const Spacer(),
              _FooterIconButton(
                tooltip: 'Automations',
                onPressed: onOpenAutomations,
                icon: AleraIcons.checks,
              ),
              const SizedBox(width: AleraTokens.space8),
              _FooterIconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                icon: AleraIcons.settings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _CollapsedSidebarFooter({
  required final VoidCallback onOpenSettings,
  required final VoidCallback onOpenAutomations,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.collapsedSidebarFooterHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AleraTokens.surface),
        child: Center(
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              _FooterIconButton(
                tooltip: 'Automations',
                onPressed: onOpenAutomations,
                icon: AleraIcons.checks,
              ),
              const SizedBox(height: AleraTokens.space8),
              _FooterIconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                icon: AleraIcons.settings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _FooterIconButton({
  required final String tooltip,
  required final VoidCallback onPressed,
  required final IconData icon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      iconSize: 15,
      backgroundColor: AleraTokens.surfaceVariant,
      borderColor: AleraTokens.borderSubtle,
    );
  }
}

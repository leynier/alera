part of 'project_workbench_sidebar.dart';

class _EmptyProjectsView extends StatelessWidget {
  const _EmptyProjectsView({required this.onAddProject});

  final VoidCallback onAddProject;

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

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.onAddProject,
    required this.onOpenSettings,
    required this.onOpenAutomations,
  });

  final VoidCallback onAddProject;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAutomations;

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

class _CollapsedSidebarFooter extends StatelessWidget {
  const _CollapsedSidebarFooter({
    required this.onOpenSettings,
    required this.onOpenAutomations,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAutomations;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.collapsedSidebarFooterHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AleraTokens.surface),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

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

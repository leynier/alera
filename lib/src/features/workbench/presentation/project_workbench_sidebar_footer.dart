part of 'project_workbench_sidebar.dart';

class _EmptyProjectsView extends StatelessWidget {
  const _EmptyProjectsView({required this.onAddProject});

  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      icon: Icons.folder_outlined,
      title: 'No projects yet',
      message: 'Add a git repository to create workspaces with terminal tabs.',
      action: FilledButton.icon(
        onPressed: onAddProject,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add your first project'),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.onAddProject,
    required this.onOpenSettings,
  });

  final VoidCallback onAddProject;
  final VoidCallback onOpenSettings;

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
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add project'),
              ),
              const Spacer(),
              _FooterIconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                icon: Icons.settings_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedSidebarFooter extends StatelessWidget {
  const _CollapsedSidebarFooter({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AleraTokens.surface),
        child: Center(
          child: _FooterIconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: Icons.settings_outlined,
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

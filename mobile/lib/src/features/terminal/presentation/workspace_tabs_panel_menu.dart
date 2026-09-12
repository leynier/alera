part of 'workspace_tabs_screen.dart';

IconData _panelIcon(WorkspacePanelDestination destination) {
  return switch (destination) {
    WorkspacePanelDestination.terminal => AleraIcons.terminal,
    WorkspacePanelDestination.explorer => AleraIcons.folder,
    WorkspacePanelDestination.search => AleraIcons.search,
    WorkspacePanelDestination.sourceControl => AleraIcons.gitBranch,
    WorkspacePanelDestination.pullRequest => AleraIcons.gitPullRequest,
  };
}

String _panelLabel(WorkspacePanelDestination destination) {
  return switch (destination) {
    WorkspacePanelDestination.terminal => 'Terminal',
    WorkspacePanelDestination.explorer => 'Explorer',
    WorkspacePanelDestination.search => 'Search',
    WorkspacePanelDestination.sourceControl => 'Source Control',
    WorkspacePanelDestination.pullRequest => 'Pull Request',
  };
}

class const _PanelMenuRow({
  required final IconData icon,
  required final String label,
  required final bool selected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: AleraTokens.foregroundMuted),
        const SizedBox(width: AleraTokens.space12),
        Expanded(child: Text(label)),
        if (selected)
          const Icon(AleraIcons.check, size: 16, color: AleraTokens.foreground),
      ],
    );
  }
}

sealed class _NewTabAction {
  const _NewTabAction();
}

class const _NewTerminalTabAction() extends _NewTabAction {}

class const _NewAgentProfileTabAction(final String profileId)
    extends _NewTabAction {}

sealed class _TabsMenuAction {
  const _TabsMenuAction();
}

class const _QuickKeysMenuAction() extends _TabsMenuAction {}

class const _SelectPanelAction(final WorkspacePanelDestination destination)
    extends _TabsMenuAction {}

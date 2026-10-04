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

class const _NewAgentProfileTabAction(final AgentProfileSummary profile)
    extends _NewTabAction {}

sealed class _TabsMenuAction {
  const _TabsMenuAction();
}

class const _QuickKeysMenuAction() extends _TabsMenuAction {}

class const _AutomationsMenuAction({final bool create = false})
    extends _TabsMenuAction {}

const List<PopupMenuEntry<_TabsMenuAction>> _automationMenuEntries =
    <PopupMenuEntry<_TabsMenuAction>>[
      PopupMenuItem<_TabsMenuAction>(
        value: _AutomationsMenuAction(),
        height: AleraTokens.minTapTarget,
        child: Text('Automations'),
      ),
      PopupMenuItem<_TabsMenuAction>(
        value: _AutomationsMenuAction(create: true),
        height: AleraTokens.minTapTarget,
        child: Text('New Automation Here'),
      ),
      PopupMenuDivider(),
    ];

/// Opens this workspace's automations; [create] starts the authoring flow with
/// the workspace as origin, never as the execution target.
void _openWorkspaceAutomations(
  BuildContext context,
  WorkspaceTabsScreen screen, {
  required bool create,
}) => unawaited(
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => AutomationsScreen(
        hostId: screen.hostId,
        initialScope: AutomationScope(
          kind: AutomationScopeKind.workspace,
          id: screen.workspace.id,
        ),
        startAuthoring: create,
      ),
    ),
  ),
);

class const _SelectPanelAction(final WorkspacePanelDestination destination)
    extends _TabsMenuAction {}

String? _automationRunId(WorkspaceTabSummary tab) =>
    switch (tab.payload['automationRunId']) {
      final String id when id.isNotEmpty => id,
      _ => null,
    };

extension on _WorkspaceTabsScreenState {
  /// An automation-owned tab attaches read-only, unless it was taken over or
  /// the runtime cannot observe; then the attach keeps its old semantics.
  bool _observes(WorkspaceTabSummary tab) {
    final client = ref.watch(hostConnectionControllerProvider(widget.hostId));
    final supported =
        client.value?.runtimeCapabilities.contains(
          automationTerminalObserveCapability,
        ) ??
        false;
    return supported &&
        mobileAutomationTabIsObserved(
          tab.payload,
          tab.id,
          ref.watch(mobileAutomationTakenOverTabsProvider(widget.hostId)),
        );
  }
}

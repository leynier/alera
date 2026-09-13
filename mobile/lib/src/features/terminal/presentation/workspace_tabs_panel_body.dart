part of 'workspace_tabs_screen.dart';

extension on _WorkspaceTabsScreenState {
  void _openTab(String tabId) {
    if (!mounted) {
      return;
    }
    setState(() => _selectedTabId = tabId);
    ref
        .read(
          selectedWorkspacePanelControllerProvider(
            widget.hostId,
            widget.workspace.id,
          ).notifier,
        )
        .select(WorkspacePanelDestination.terminal);
  }

  Widget _panelBody(WorkspacePanelDestination panel) {
    final hostId = widget.hostId;
    final workspaceId = widget.workspace.id;
    return switch (panel) {
      WorkspacePanelDestination.explorer => ExplorerPanel(
        hostId: hostId,
        workspace: widget.workspace,
        onOpenTab: _openTab,
      ),
      WorkspacePanelDestination.search => WorkspaceTextSearchPanel(
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      WorkspacePanelDestination.sourceControl => SourceControlPanel(
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      WorkspacePanelDestination.pullRequest => PullRequestPanel(
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      WorkspacePanelDestination.terminal => _terminalBody(
        ref.watch(tabsControllerProvider(widget.hostId, widget.workspace.id)),
      ),
    };
  }
}

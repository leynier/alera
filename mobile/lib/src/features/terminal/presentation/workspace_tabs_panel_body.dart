part of 'workspace_tabs_screen.dart';

extension _WorkspaceTabsPanelBody on _WorkspaceTabsScreenState {
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
        onOpenTab: _openTab,
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

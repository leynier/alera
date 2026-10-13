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

  /// A chat tab whose payload lost its chat id cannot be opened; the runtime
  /// writes that key, so this only happens with a damaged tab record.
  Widget _agentChatBody(WorkspaceTabSummary tab) {
    final chatId = tab.agentChatId;
    if (chatId == null) {
      return const AleraEmptyState(
        icon: AleraIcons.loadFailed,
        title: 'Chat unavailable',
        message: 'This tab does not name a chat on the host.',
      );
    }
    return AgentChatTabView(
      key: ValueKey<String>(tab.id),
      hostId: widget.hostId,
      workspaceId: tab.workspaceId,
      chatId: chatId,
      provider: tab.agentChatProvider ?? '',
      remoteWorkspace: widget.workspace.isOnRemoteHost,
      onOpenTab: _openTab,
    );
  }
}

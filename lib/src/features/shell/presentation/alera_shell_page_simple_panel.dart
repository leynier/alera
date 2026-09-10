part of 'alera_shell_page.dart';

extension _SimplePanelTabs on _AleraShellPageBodyState {
  Widget _buildSimplePanelTab({
    required Workspace workspace,
    required SimpleWorkspacePanel panel,
    required List<WorkspaceTabRecord> tabs,
    required WorkspaceTabRecord tab,
    required bool active,
    required String groupId,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final tabsById = <String, WorkspaceTabRecord>{
      for (final record in tabs) record.id: record,
    };
    final panelTabs = <WorkspaceTabRecord>[
      for (final key in panel.tabKeys)
        if (tabsById[SimpleWorkspacePanel.tabId(key)]
            case final WorkspaceTabRecord record)
          record,
    ];
    return Consumer(
      builder: (context, ref, _) {
        final status = ref.watch(
          agentStatusControllerProvider.select(
            (statuses) => statuses[tab.terminalSessionId],
          ),
        );
        return buildSimpleWorkspaceTabChip(
          tab: tab,
          tabs: panelTabs,
          active: active,
          runtime: ref.read(terminalRuntimeProvider),
          status: status,
          acknowledgements: _completionAcknowledgements,
          onSelect: () => controller.selectSimplePanelKey(
            workspace.id,
            SimpleWorkspacePanel.tabKey(tab.id),
          ),
          onCloseTabs: (ids) async {
            if (await _confirmCloseDirtyTabs(tabs, ids)) {
              await controller.closeWorkspaceTabs(
                workspace: workspace,
                tabIds: ids,
              );
            }
          },
          onRename: (title) => unawaited(
            controller.renameWorkspaceTab(tabId: tab.id, title: title),
          ),
          onKeep: (id) => unawaited(controller.keepPreviewTab(id)),
          onSplit: (zone) => unawaited(
            controller.splitWorkbenchGroupWithTerminal(
              workspace: workspace,
              groupId: groupId,
              zone: zone,
            ),
          ),
        );
      },
    );
  }
}

part of 'alera_shell_page.dart';

extension _SimplePanelTabs on _AleraShellPageBodyState {
  Widget _buildSimplePanelView({
    required Workspace workspace,
    required Project? project,
    required SimpleWorkspacePanel panel,
    required WorkspaceSourceControlScope? sourceControlScope,
    required List<WorkspaceTabRecord> tabs,
    required bool bootstrapped,
    required bool hasProjects,
    required WorkbenchLayout? layout,
    required Widget Function(WorkbenchContextPanelTab tab) toolFor,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    return SimpleWorkspacePanelView(
      workspaceId: workspace.id,
      panel: panel,
      tabs: tabs,
      tabBuilder: (tab, active, groupId) => _buildSimplePanelTab(
        workspace: workspace,
        panel: panel,
        tabs: tabs,
        tab: tab,
        active: active,
        groupId: groupId,
      ),
      onSelect: (key) => controller.selectSimplePanelKey(workspace.id, key),
      onSelectInGroup: (groupId, key) =>
          controller.selectSimplePanelKey(workspace.id, key, groupId: groupId),
      onClose: (key) async {
        final tool = SimpleWorkspaceTool.forKey(key);
        if (tool != null) {
          controller.closeSimpleTool(workspace.id, tool);
        } else if (SimpleWorkspacePanel.tabId(key) case final String id) {
          if (await _confirmCloseDirtyTabs(tabs, <String>[id])) {
            await controller.closeWorkspaceTab(workspace: workspace, tabId: id);
          }
        }
      },
      onNewTerminal: () => unawaited(controller.createTerminalTab(workspace)),
      onNewTerminalInGroup: (groupId) {
        unawaited(
          controller.createTerminalTab(workspace, targetGroupId: groupId),
        );
      },
      onSplitGroup: (groupId, zone) {
        unawaited(
          controller.splitWorkbenchGroupWithTerminal(
            workspace: workspace,
            groupId: groupId,
            zone: zone,
          ),
        );
      },
      onMergeGroup: (groupId) {
        unawaited(
          controller.mergeWorkbenchGroupIntoSibling(
            workspaceId: workspace.id,
            groupId: groupId,
          ),
        );
      },
      onMoveTab:
          ({required key, required targetGroupId, required zone, index}) {
            unawaited(
              controller.moveWorkspaceTab(
                workspaceId: workspace.id,
                tabId: key,
                targetGroupId: targetGroupId,
                zone: zone,
                index: index,
              ),
            );
          },
      onUpdateSplitRatio: (path, ratio) {
        controller.updateWorkbenchSplitRatio(
          workspaceId: workspace.id,
          nodePath: path,
          ratio: ratio,
        );
      },
      onHide: controller.toggleRightSidebarVisible,
      surfaceBuilder: (key) {
        final tool = SimpleWorkspaceTool.forKey(key);
        if (tool != null) {
          return Focus(
            canRequestFocus: false,
            onFocusChange: (focused) {
              if (focused) {
                controller.selectSimplePanelKey(workspace.id, key);
              }
            },
            child: toolFor(switch (tool) {
              SimpleWorkspaceTool.explorer => WorkbenchContextPanelTab.explorer,
              SimpleWorkspaceTool.search => WorkbenchContextPanelTab.search,
              SimpleWorkspaceTool.sourceControl =>
                WorkbenchContextPanelTab.gitDiff,
              SimpleWorkspaceTool.pullRequest =>
                WorkbenchContextPanelTab.pullRequests,
            }),
          );
        }
        return _buildContent(
          bootstrapped: bootstrapped,
          hasProjects: hasProjects,
          project: project,
          workspace: workspace,
          sourceControlScope: sourceControlScope,
          tabs: tabs,
          layout: layout,
          singleSurface: true,
          singleTabId: SimpleWorkspacePanel.tabId(key),
        );
      },
      content: const SizedBox.shrink(),
    );
  }

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

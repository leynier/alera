part of 'alera_shell_page.dart';

extension _ExperimentalPanelTabs on _AleraShellPageBodyState {
  Widget _buildExperimentalPanelView({
    required Workspace workspace,
    required Project? project,
    required ExperimentalWorkspacePanel panel,
    required WorkspaceSourceControlScope? sourceControlScope,
    required List<WorkspaceTabRecord> tabs,
    required bool bootstrapped,
    required bool hasProjects,
    required WorkbenchLayout? layout,
    required Widget Function(WorkbenchContextPanelTab tab) toolFor,
    ExperimentalPanelTree tree = ExperimentalPanelTree.right,
    bool showHide = true,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    return ExperimentalWorkspacePanelView(
      workspaceId: workspace.id,
      panel: panel,
      tabs: tabs,
      tabBuilder: (tab, active, groupId) => _buildExperimentalPanelTab(
        workspace: workspace,
        panel: panel,
        tabs: tabs,
        tab: tab,
        active: active,
        tree: tree,
        groupId: groupId,
      ),
      onSelect: (key) =>
          controller.selectExperimentalPanelKey(workspace.id, key),
      onSelectInGroup: (groupId, key) => controller.selectExperimentalPanelKey(
        workspace.id,
        key,
        groupId: groupId,
      ),
      onClose: (key) async {
        final tool = ExperimentalWorkspaceTool.forKey(key);
        if (tool != null) {
          controller.closeExperimentalTool(workspace.id, tool);
        } else if (ExperimentalWorkspacePanel.tabId(key) case final String id) {
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
          ({
            required key,
            required targetGroupId,
            required zone,
            required source,
            index,
          }) {
            unawaited(
              controller.moveExperimentalPaneTab(
                workspaceId: workspace.id,
                tabId: key,
                targetGroupId: targetGroupId,
                zone: zone,
                index: index,
                source: source,
                target: tree,
              ),
            );
          },
      onUpdateSplitRatio: (path, ratio) {
        controller.updateExperimentalPaneSplitRatio(
          workspaceId: workspace.id,
          nodePath: path,
          ratio: ratio,
          tree: tree,
        );
      },
      tree: tree,
      showHide: showHide,
      onHide: controller.toggleRightSidebarVisible,
      surfaceBuilder: (key) {
        final tool = ExperimentalWorkspaceTool.forKey(key);
        if (tool != null) {
          return Focus(
            canRequestFocus: false,
            onFocusChange: (focused) {
              if (focused) {
                controller.selectExperimentalPanelKey(workspace.id, key);
              }
            },
            child: _experimentalToolSurface(tool, toolFor),
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
          singleTabId: ExperimentalWorkspacePanel.tabId(key),
        );
      },
      content: const SizedBox.shrink(),
    );
  }

  Widget _buildExperimentalCenter({
    required Workspace workspace,
    required Project? project,
    required ExperimentalWorkspacePanel panel,
    required WorkspaceSourceControlScope? sourceControlScope,
    required List<WorkspaceTabRecord> tabs,
    required bool bootstrapped,
    required bool hasProjects,
    required WorkbenchLayout? layout,
    required Widget Function(WorkbenchContextPanelTab tab) toolFor,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    if (panel.showsMainChrome) {
      return _buildExperimentalPanelView(
        workspace: workspace,
        project: project,
        panel: panel,
        sourceControlScope: sourceControlScope,
        tabs: tabs,
        bootstrapped: bootstrapped,
        hasProjects: hasProjects,
        layout: layout,
        toolFor: toolFor,
        tree: ExperimentalPanelTree.main,
        showHide: false,
      );
    }
    final main = panel.ensuredMainLayout(workspace.id);
    final key = panel.mainKeys.firstOrNull;
    final tool = ExperimentalWorkspaceTool.forKey(key);
    final surface = tool != null
        ? _experimentalToolSurface(tool, toolFor)
        : _buildContent(
            bootstrapped: bootstrapped,
            hasProjects: hasProjects,
            project: project,
            workspace: workspace,
            sourceControlScope: sourceControlScope,
            tabs: tabs,
            layout: layout,
            singleSurface: true,
            singleTabId:
                ExperimentalWorkspacePanel.tabId(key) ?? panel.primaryTabId,
          );
    return ExperimentalMainDropSurface(
      workspaceId: workspace.id,
      groupId: main.activeGroupId,
      onMoveTab:
          ({
            required key,
            required targetGroupId,
            required zone,
            required source,
            index,
          }) {
            unawaited(
              controller.moveExperimentalPaneTab(
                workspaceId: workspace.id,
                tabId: key,
                targetGroupId: targetGroupId,
                zone: zone,
                index: index,
                source: source,
                target: ExperimentalPanelTree.main,
              ),
            );
          },
      child: surface,
    );
  }

  Widget _buildExperimentalPanelTab({
    required Workspace workspace,
    required ExperimentalWorkspacePanel panel,
    required List<WorkspaceTabRecord> tabs,
    required WorkspaceTabRecord tab,
    required bool active,
    required String groupId,
    ExperimentalPanelTree tree = ExperimentalPanelTree.right,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final tabsById = <String, WorkspaceTabRecord>{
      for (final record in tabs) record.id: record,
    };
    final keys = tree == ExperimentalPanelTree.main
        ? panel.mainKeys
        : panel.tabKeys;
    final panelTabs = <WorkspaceTabRecord>[
      for (final key in keys)
        if (tabsById[ExperimentalWorkspacePanel.tabId(key)]
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
        return buildExperimentalWorkspaceTabChip(
          tab: tab,
          tabs: panelTabs,
          active: active,
          runtime: ref.read(terminalRuntimeProvider),
          status: status,
          acknowledgements: _completionAcknowledgements,
          onSelect: () => controller.selectExperimentalPanelKey(
            workspace.id,
            ExperimentalWorkspacePanel.tabKey(tab.id),
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

  Widget _experimentalToolSurface(
    ExperimentalWorkspaceTool tool,
    Widget Function(WorkbenchContextPanelTab tab) toolFor,
  ) {
    return ColoredBox(
      color: AleraTokens.surfaceVariant,
      child: toolFor(switch (tool) {
        ExperimentalWorkspaceTool.explorer => WorkbenchContextPanelTab.explorer,
        ExperimentalWorkspaceTool.search => WorkbenchContextPanelTab.search,
        ExperimentalWorkspaceTool.sourceControl =>
          WorkbenchContextPanelTab.gitDiff,
        ExperimentalWorkspaceTool.pullRequest =>
          WorkbenchContextPanelTab.pullRequests,
      }),
    );
  }
}

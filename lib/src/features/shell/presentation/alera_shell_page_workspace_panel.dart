part of 'alera_shell_page.dart';

extension _WorkspacePanelTabs on _AleraShellPageBodyState {
  Widget _buildWorkspacePanelView({
    required Workspace workspace,
    required Project? project,
    required WorkspacePanel panel,
    required WorkspaceSourceControlScope? sourceControlScope,
    required List<WorkspaceTabRecord> tabs,
    required bool bootstrapped,
    required bool hasProjects,
    required WorkbenchLayout? layout,
    required Widget Function(WorkbenchContextPanelTab tab) toolFor,
    WorkspacePanelTree tree = WorkspacePanelTree.right,
    bool showHide = true,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final newTabMenuProfiles =
        ref.watch(agentProfilesProvider).asData?.value ??
        const <AgentProfile>[];
    return WorkspacePanelView(
      workspaceId: workspace.id,
      panel: panel,
      tabs: tabs,
      newTabMenuProfiles: newTabMenuProfiles,
      onLaunchAgentProfile: ({required profileId, targetGroupId}) {
        final profile = newTabMenuProfiles
            .where((candidate) => candidate.id == profileId)
            .firstOrNull;
        if (profile == null) {
          return;
        }
        unawaited(
          _launchAgentProfileFromMenu(
            workspace: workspace,
            profile: profile,
            targetGroupId: targetGroupId,
          ),
        );
      },
      tabBuilder: (tab, active, groupId) => _buildWorkspacePanelTab(
        workspace: workspace,
        panel: panel,
        tabs: tabs,
        tab: tab,
        active: active,
        tree: tree,
        groupId: groupId,
      ),
      onSelect: (key) => controller.selectWorkspacePanelKey(workspace.id, key),
      onSelectInGroup: (groupId, key) => controller.selectWorkspacePanelKey(
        workspace.id,
        key,
        groupId: groupId,
      ),
      onClose: (key) async {
        final tool = WorkspaceTool.forKey(key);
        if (tool != null) {
          controller.closeWorkspaceTool(workspace.id, tool);
        } else if (WorkspacePanel.tabId(key) case final String id) {
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
              controller.moveWorkspacePaneTab(
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
        controller.updateWorkspacePaneSplitRatio(
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
        final tool = WorkspaceTool.forKey(key);
        if (tool != null) {
          // A scope, like the workbench panes: focus released inside this
          // tool must not land on a sibling surface and reselect its key.
          return WorkbenchRegisteredFocusScope(
            registryKey: key,
            registry: ref.read(workbenchPaneFocusRegistryProvider),
            debugLabel: 'WorkspaceTool $key',
            onFocusChange: (focused) {
              if (focused) {
                controller.selectWorkspacePanelKey(workspace.id, key);
              }
            },
            child: _workspaceToolSurface(tool, toolFor),
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
          singleTabId: WorkspacePanel.tabId(key),
        );
      },
      content: const SizedBox.shrink(),
    );
  }

  Widget _buildWorkspaceCenter({
    required Workspace workspace,
    required Project? project,
    required WorkspacePanel panel,
    required WorkspaceSourceControlScope? sourceControlScope,
    required List<WorkspaceTabRecord> tabs,
    required bool bootstrapped,
    required bool hasProjects,
    required WorkbenchLayout? layout,
    required Widget Function(WorkbenchContextPanelTab tab) toolFor,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    if (panel.showsMainChrome) {
      return _buildWorkspacePanelView(
        workspace: workspace,
        project: project,
        panel: panel,
        sourceControlScope: sourceControlScope,
        tabs: tabs,
        bootstrapped: bootstrapped,
        hasProjects: hasProjects,
        layout: layout,
        toolFor: toolFor,
        tree: WorkspacePanelTree.main,
        showHide: false,
      );
    }
    final main = panel.ensuredMainLayout(workspace.id);
    final key = panel.mainKeys.firstOrNull;
    final tool = WorkspaceTool.forKey(key);
    final surface = tool != null
        ? Focus(
            canRequestFocus: false,
            onFocusChange: (focused) {
              if (focused && key != null) {
                controller.selectWorkspacePanelKey(workspace.id, key);
              }
            },
            child: _workspaceToolSurface(tool, toolFor),
          )
        : _buildContent(
            bootstrapped: bootstrapped,
            hasProjects: hasProjects,
            project: project,
            workspace: workspace,
            sourceControlScope: sourceControlScope,
            tabs: tabs,
            layout: layout,
            singleSurface: true,
            singleTabId: WorkspacePanel.tabId(key) ?? panel.primaryTabId,
          );
    return WorkspaceMainDropSurface(
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
              controller.moveWorkspacePaneTab(
                workspaceId: workspace.id,
                tabId: key,
                targetGroupId: targetGroupId,
                zone: zone,
                index: index,
                source: source,
                target: WorkspacePanelTree.main,
              ),
            );
          },
      child: surface,
    );
  }

  Widget _buildWorkspacePanelTab({
    required Workspace workspace,
    required WorkspacePanel panel,
    required List<WorkspaceTabRecord> tabs,
    required WorkspaceTabRecord tab,
    required bool active,
    required String groupId,
    WorkspacePanelTree tree = WorkspacePanelTree.right,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final tabsById = <String, WorkspaceTabRecord>{
      for (final record in tabs) record.id: record,
    };
    final keys = tree == WorkspacePanelTree.main
        ? panel.mainKeys
        : panel.tabKeys;
    final panelTabs = <WorkspaceTabRecord>[
      for (final key in keys)
        if (tabsById[WorkspacePanel.tabId(key)]
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
        return buildWorkspacePanelTabChip(
          tab: tab,
          tabs: panelTabs,
          active: active,
          runtime: ref.read(terminalRuntimeProvider),
          status: status,
          acknowledgements: _completionAcknowledgements,
          onSelect: () => controller.selectWorkspacePanelKey(
            workspace.id,
            WorkspacePanel.tabKey(tab.id),
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

  Widget _workspaceToolSurface(
    WorkspaceTool tool,
    Widget Function(WorkbenchContextPanelTab tab) toolFor,
  ) {
    return ColoredBox(
      color: AleraTokens.surfaceVariant,
      child: toolFor(switch (tool) {
        WorkspaceTool.explorer => WorkbenchContextPanelTab.explorer,
        WorkspaceTool.search => WorkbenchContextPanelTab.search,
        WorkspaceTool.sourceControl => WorkbenchContextPanelTab.gitDiff,
        WorkspaceTool.pullRequest => WorkbenchContextPanelTab.pullRequests,
      }),
    );
  }
}

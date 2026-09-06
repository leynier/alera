part of 'alera_shell_page.dart';

extension _AleraShellPageBodyContent on _AleraShellPageBodyState {
  Widget _buildContent({
    required bool bootstrapped,
    required bool hasProjects,
    required Project? project,
    required Workspace? workspace,
    required WorkspaceSourceControlScope? sourceControlScope,
    required List<WorkspaceTabRecord> tabs,
    required WorkbenchLayout? layout,
  }) {
    if (!bootstrapped && !hasProjects) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!hasProjects || project == null || workspace == null) {
      return const WelcomeDashboard();
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    final terminalRuntime = ref.read(terminalRuntimeProvider);
    return Consumer(
      builder: (context, ref, _) {
        // Watch only the statuses of this workspace's sessions, so an agent
        // transition in another workspace does not rebuild the whole
        // workbench tree. Unchanged sessions keep their entry instance, which
        // is what makes the per-session select cheap.
        final agentStatuses = <String, AgentStatusEntry>{};
        for (final tab in tabs) {
          final sessionId = tab.terminalSessionId;
          final entry = ref.watch(
            agentStatusControllerProvider.select(
              (statuses) => statuses[sessionId],
            ),
          );
          if (entry != null) {
            agentStatuses[sessionId] = entry;
          }
        }
        final mobileDrivers = ref.watch(
          terminalDriverPresenceControllerProvider,
        );
        final driverPresence = ref.read(
          terminalDriverPresenceControllerProvider.notifier,
        );
        return WorkspaceWorkbenchView(
          project: project,
          workspace: workspace,
          sourceControlScope: sourceControlScope,
          tabs: tabs,
          layout: layout,
          terminalRuntime: terminalRuntime,
          mobileDriverPresence: WorkbenchMobileDriverPresence(
            drivers: mobileDrivers,
            onReclaim: (sessionId) =>
                unawaited(driverPresence.reclaim(sessionId)),
            onReclaimAll: () => unawaited(driverPresence.reclaimAll()),
          ),
          agentStatuses: agentStatuses,
          completionAcknowledgements: _completionAcknowledgements,
          onCreateTab: ({targetGroupId}) async {
            final tab = await controller.createTerminalTab(
              workspace,
              targetGroupId: targetGroupId,
            );
            terminalRuntime
                .sessionFor(workspace: workspace, tab: tab)
                .requestFocus();
          },
          onOpenEditorTab: ({required relativePath, targetGroupId}) async {
            await controller.openEditorTab(
              workspace: workspace,
              relativePath: relativePath,
              targetGroupId: targetGroupId,
            );
          },
          onOpenMarkdownViewerTab:
              ({required relativePath, targetGroupId}) async {
                await controller.openMarkdownViewerTab(
                  workspace: workspace,
                  relativePath: relativePath,
                  targetGroupId: targetGroupId,
                );
              },
          onKeepPreviewTab: (tabId) {
            unawaited(controller.keepPreviewTab(tabId));
          },
          onSelectTab: ({required groupId, required tabId}) {
            controller.setActiveWorkspaceTab(
              workspaceId: workspace.id,
              groupId: groupId,
              tabId: tabId,
            );
          },
          onCloseTab: (tabId) async {
            if (!await _confirmCloseDirtyTabs(tabs, <String>[tabId])) {
              return;
            }
            // The controller disposes the terminal handle and editor document.
            await controller.closeWorkspaceTab(
              workspace: workspace,
              tabId: tabId,
            );
          },
          onCloseTabs: (tabIds) async {
            if (!await _confirmCloseDirtyTabs(tabs, tabIds)) {
              return;
            }
            // The controller disposes the terminal handles and editor
            // documents.
            await controller.closeWorkspaceTabs(
              workspace: workspace,
              tabIds: tabIds,
            );
          },
          onRenameTab: ({required tabId, required title}) async {
            await controller.renameWorkspaceTab(tabId: tabId, title: title);
          },
          onOpenEditor: (relativePath) async {
            await controller.openEditorTab(
              workspace: workspace,
              relativePath: relativePath,
            );
          },
          onOpenMermanPreview: (relativePath) async {
            await controller.openMermanPreviewTab(
              workspace: workspace,
              relativePath: relativePath,
            );
          },
          onMoveTab:
              ({
                required tabId,
                required targetGroupId,
                required zone,
                int? index,
              }) async {
                await controller.moveWorkspaceTab(
                  workspaceId: workspace.id,
                  tabId: tabId,
                  targetGroupId: targetGroupId,
                  zone: zone,
                  index: index,
                );
              },
          onSplitGroup: ({required groupId, required zone}) async {
            final tab = await controller.splitWorkbenchGroupWithTerminal(
              workspace: workspace,
              groupId: groupId,
              zone: zone,
            );
            terminalRuntime
                .sessionFor(workspace: workspace, tab: tab)
                .requestFocus();
          },
          onMergeGroup: ({required groupId}) async {
            await controller.mergeWorkbenchGroupIntoSibling(
              workspaceId: workspace.id,
              groupId: groupId,
            );
          },
          onActivateGroup: ({required groupId}) {
            controller.focusWorkbenchGroup(
              workspaceId: workspace.id,
              groupId: groupId,
            );
          },
          onUpdateSplitRatio: ({required nodePath, required ratio}) {
            controller.updateWorkbenchSplitRatio(
              workspaceId: workspace.id,
              nodePath: nodePath,
              ratio: ratio,
            );
          },
        );
      },
    );
  }
}

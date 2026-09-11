part of 'alera_shell_page.dart';

extension _AleraShellPageBodyContent on _AleraShellPageBodyState {
  Future<void> _launchAgentProfileFromMenu({
    required Workspace workspace,
    required AgentProfile profile,
    String? targetGroupId,
  }) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final terminalRuntime = ref.read(terminalRuntimeProvider);
    await showAgentProfileLaunchDialog(
      context,
      profile: profile,
      workspacePath: workspace.path,
      onLaunch: ({required prompt}) async {
        final tabId = await controller.launchAgentProfileTab(
          workspace: workspace,
          profileId: profile.id,
          targetGroupId: targetGroupId,
          prompt: prompt,
        );
        final tab = ref
            .read(workbenchControllerProvider)
            .tabsFor(workspace.id)
            .where((candidate) => candidate.id == tabId)
            .firstOrNull;
        if (tab == null) {
          return;
        }
        terminalRuntime
            .sessionFor(workspace: workspace, tab: tab)
            .requestFocus();
      },
    );
  }

  Widget _buildContent({
    required bool bootstrapped,
    required bool hasProjects,
    required Project? project,
    required Workspace? workspace,
    required WorkspaceSourceControlScope? sourceControlScope,
    required List<WorkspaceTabRecord> tabs,
    required WorkbenchLayout? layout,
    bool singleSurface = false,
    String? singleTabId,
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
        final newTabMenuProfiles =
            ref.watch(agentProfilesProvider).asData?.value ??
            const <AgentProfile>[];
        return WorkspaceWorkbenchView(
          key: ValueKey((workspace.id, singleSurface, singleTabId)),
          singleSurface: singleSurface,
          singleTabId: singleTabId,
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
          newTabMenuProfiles: <AgentProfile>[
            for (final profile in newTabMenuProfiles)
              if (profile.showInNewTabMenu) profile,
          ],
          onLaunchAgentProfile: ({required profileId, targetGroupId}) async {
            final profile = newTabMenuProfiles
                .where((candidate) => candidate.id == profileId)
                .firstOrNull;
            if (profile == null) {
              return;
            }
            await _launchAgentProfileFromMenu(
              workspace: workspace,
              profile: profile,
              targetGroupId: targetGroupId,
            );
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

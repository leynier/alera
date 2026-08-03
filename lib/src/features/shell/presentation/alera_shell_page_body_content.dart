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
    required bool browserTabsAvailable,
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
        final agentStatuses = ref.watch(agentStatusControllerProvider);
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
          onCreateBrowserTab: browserTabsAvailable
              ? ({targetGroupId}) async {
                  await controller.createBrowserTab(
                    workspace,
                    targetGroupId: targetGroupId,
                  );
                }
              : null,
          onCreateCodexTab: ({targetGroupId}) async {
            await controller.createCodexTab(
              workspace,
              targetGroupId: targetGroupId,
            );
          },
          onOpenMobileEmulator: ({targetGroupId}) async {
            final existing = tabs.any(
              (tab) => tab.kind == WorkspaceTabKind.mobileEmulator,
            );
            if (existing) {
              await controller.openMobileEmulatorTab(
                workspace: workspace,
                targetGroupId: targetGroupId,
              );
              return;
            }
            final device = await showMobileEmulatorDevicePicker(context);
            if (device == null || !mounted) {
              return;
            }
            await controller.openMobileEmulatorTab(
              workspace: workspace,
              platform: device.platform,
              deviceId: device.id,
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
            final closingTab = _workspaceTabById(tabs, tabId);
            terminalRuntime.closeTab(tabId);
            await controller.closeWorkspaceTab(
              workspace: workspace,
              tabId: tabId,
            );
            if (closingTab?.kind == WorkspaceTabKind.browser) {
              await ref.read(browserSessionRegistryProvider).closePage(tabId);
            }
            ref.read(editorSessionRegistryProvider).forget(tabId);
          },
          onCloseTabs: (tabIds) async {
            if (!await _confirmCloseDirtyTabs(tabs, tabIds)) {
              return;
            }
            final browserTabIds = <String>[
              for (final tabId in tabIds)
                if (_workspaceTabById(tabs, tabId)?.kind ==
                    WorkspaceTabKind.browser)
                  tabId,
            ];
            for (final tabId in tabIds) {
              terminalRuntime.closeTab(tabId);
            }
            await controller.closeWorkspaceTabs(
              workspace: workspace,
              tabIds: tabIds,
            );
            await Future.wait(<Future<void>>[
              for (final tabId in browserTabIds)
                ref.read(browserSessionRegistryProvider).closePage(tabId),
            ]);
            final registry = ref.read(editorSessionRegistryProvider);
            for (final tabId in tabIds) {
              registry.forget(tabId);
            }
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

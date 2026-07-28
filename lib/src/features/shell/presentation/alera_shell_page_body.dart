part of 'alera_shell_page.dart';

class _AleraShellPageBodyState extends ConsumerState<_AleraShellPageBody> {
  String? _lastErrorMessage;
  final WorkbenchTabCompletionAcknowledgements _completionAcknowledgements =
      WorkbenchTabCompletionAcknowledgements();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(workbenchControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(terminalHostWarmupCoordinatorProvider);
    ref.watch(runtimeAgentStatusSyncProvider);
    ref.watch(agentStatusNotificationCoordinatorProvider);
    ref.watch(agentAwakeCoordinatorProvider);
    ref.watch(terminalRuntimeExitCoordinatorProvider);
    ref.watch(workspaceActivityCoordinatorProvider);
    ref.watch(terminalRuntimeActiveWorkspaceCoordinatorProvider);
    ref.watch(workspaceActivityPersistenceCoordinatorProvider);
    ref.watch(browserEventDispatcherProvider);
    final browserTabsAvailable =
        ref.watch(browserAvailabilityProvider).asData?.value.meetsStableGate ==
        true;
    final shell = ref.watch(
      workbenchControllerProvider.select((state) {
        final workspace = state.activeWorkspace;
        return (
          activeProject: state.activeProject,
          activeWorkspace: workspace,
          bootstrapped: state.bootstrapped,
          collapsed: state.collapsed,
          error: state.error,
          hasProjects: state.projects.isNotEmpty,
          layout: workspace == null ? null : state.layoutFor(workspace.id),
          tabs: workspace == null
              ? const <WorkspaceTabRecord>[]
              : state.tabsFor(workspace.id),
          tabsByWorkspace: state.tabsByWorkspace,
          viewPrefs: state.viewPrefs,
        );
      }),
    );
    _completionAcknowledgements.retainTerminalSessions(<String>{
      for (final tabs in shell.tabsByWorkspace.values)
        for (final tab in tabs)
          if (tab.kind == WorkspaceTabKind.terminal) tab.terminalSessionId,
    });
    final error = shell.error;
    if (error != null && error != _lastErrorMessage) {
      _lastErrorMessage = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showError(error);
      });
    }

    final project = shell.activeProject;
    final workspace = shell.activeWorkspace;
    final controller = ref.read(workbenchControllerProvider.notifier);
    final canSelectSourceControlRoot = project?.isFolder == true;
    final sourceControlScope = WorkspaceSourceControlScope.resolve(
      project: project,
      workspace: workspace,
      prefs: shell.viewPrefs,
    );

    final content = AleraAppMenuScope(
      child: Scaffold(
        body: KeyboardShortcutsScope(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showContextSidebar =
                  workspace != null &&
                  _canShowContextSidebar(
                    shellWidth: constraints.maxWidth,
                    collapsed: shell.collapsed,
                    prefs: shell.viewPrefs,
                  );
              return Column(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const ProjectWorkbenchSidebar(),
                        Expanded(
                          child: _buildContent(
                            bootstrapped: shell.bootstrapped,
                            hasProjects: shell.hasProjects,
                            project: project,
                            workspace: workspace,
                            sourceControlScope: sourceControlScope,
                            tabs: shell.tabs,
                            layout: shell.layout,
                            browserTabsAvailable: browserTabsAvailable,
                          ),
                        ),
                        if (workspace != null && showContextSidebar)
                          WorkspaceContextSidebar(
                            workspace: workspace,
                            prefs: shell.viewPrefs,
                            sourceControlScope: sourceControlScope,
                            sourceControlAvailable: sourceControlScope != null,
                            focusedSourceControlRoot: canSelectSourceControlRoot
                                ? shell
                                      .viewPrefs
                                      .sourceControlRootByWorkspaceId[workspace
                                      .id]
                                : null,
                            onToggleVisible:
                                controller.toggleRightSidebarVisible,
                            onResize: controller.setRightSidebarWidth,
                            onSetContextPanelTab: controller.setContextPanelTab,
                            onSetExplorerMode: controller.setExplorerMode,
                            onSetGitDiffViewMode: controller.setGitDiffViewMode,
                            onFocusSourceControlFolder:
                                canSelectSourceControlRoot
                                ? (relativePath) {
                                    return controller.focusSourceControlFolder(
                                      workspace: workspace,
                                      relativePath: relativePath,
                                    );
                                  }
                                : null,
                            onClearSourceControlRoot: canSelectSourceControlRoot
                                ? () {
                                    controller.clearFocusedSourceControlFolder(
                                      workspace: workspace,
                                    );
                                  }
                                : null,
                            onOpenFile: (relativePath) {
                              unawaited(
                                controller.openFileTab(
                                  workspace: workspace,
                                  relativePath: relativePath,
                                ),
                              );
                            },
                            onOpenGitDiff:
                                ({
                                  relativePath,
                                  area,
                                  gitDiffRoot,
                                  required scope,
                                }) {
                                  return controller.openGitDiffTab(
                                    workspace: workspace,
                                    relativePath: relativePath,
                                    area: area,
                                    scope: scope,
                                    gitDiffRoot: gitDiffRoot,
                                  );
                                },
                            onOpenGitCommitDiff:
                                ({
                                  relativePath,
                                  oldPath,
                                  required scope,
                                  gitDiffRoot,
                                  required commitOid,
                                  parentOid,
                                  required compareRef,
                                  subject,
                                  message,
                                }) {
                                  return controller.openGitCommitDiffTab(
                                    workspace: workspace,
                                    relativePath: relativePath,
                                    oldPath: oldPath,
                                    scope: scope,
                                    gitDiffRoot: gitDiffRoot,
                                    commitOid: commitOid,
                                    parentOid: parentOid,
                                    compareRef: compareRef,
                                    subject: subject,
                                    message: message,
                                  );
                                },
                            onOpenSearchMatch: (target) {
                              unawaited(() async {
                                final tab = await controller.openEditorTab(
                                  workspace: workspace,
                                  relativePath: target.relativePath,
                                );
                                ref
                                    .read(editorSessionRegistryProvider)
                                    .reveal(
                                      tab.id,
                                      WorkspaceEditorRevealTarget(
                                        line: target.line,
                                        column: target.column,
                                        matchLength: target.matchLength,
                                      ),
                                    );
                              }());
                            },
                            onPathMoved:
                                (oldRelativePath, newRelativePath) async {
                                  await controller.syncFileTabsAfterPathMove(
                                    workspace: workspace,
                                    oldRelativePath: oldRelativePath,
                                    newRelativePath: newRelativePath,
                                  );
                                  ref
                                      .read(editorSessionRegistryProvider)
                                      .updateDocumentPathsAfterMove(
                                        workspacePath: workspace.path,
                                        oldRelativePath: oldRelativePath,
                                        newRelativePath: newRelativePath,
                                      );
                                  controller.syncSourceControlRootAfterPathMove(
                                    workspace: workspace,
                                    oldRelativePath: oldRelativePath,
                                    newRelativePath: newRelativePath,
                                  );
                                },
                          ),
                      ],
                    ),
                  ),
                  const AgentQuotaStatusBar(
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ResourceStatusBarControl(),
                        RuntimeHostStatusBarControl(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    return BrowserNativeCallbackScope(child: content);
  }

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

  Future<bool> _confirmCloseDirtyTabs(
    List<WorkspaceTabRecord> tabs,
    List<String> tabIds,
  ) async {
    final registry = ref.read(editorSessionRegistryProvider);
    final dirty = <String>[
      for (final tab in tabs)
        if (tabIds.contains(tab.id) && registry.isDirty(tab.id)) tab.title,
    ];
    if (dirty.isEmpty) {
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AleraConfirmDialog(
        title: dirty.length == 1
            ? 'Close Unsaved Editor?'
            : 'Close Unsaved Editors?',
        message: dirty.length == 1
            ? '${dirty.first} has unsaved changes.'
            : '${dirty.length} editor tabs have unsaved changes.',
        confirmLabel: 'Close',
        destructive: true,
      ),
    );
    return confirmed == true;
  }

  void _showError(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.error);
  }
}

WorkspaceTabRecord? _workspaceTabById(
  List<WorkspaceTabRecord> tabs,
  String tabId,
) {
  for (final tab in tabs) {
    if (tab.id == tabId) {
      return tab;
    }
  }
  return null;
}

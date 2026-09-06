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
    ref.watch(workspacePullRequestMonitorControllerProvider.notifier);
    ref.watch(workspacePullRequestFailureNotificationCoordinatorProvider);
    ref.watch(agentAwakeCoordinatorProvider);
    ref.watch(keepAliveCoordinatorProvider);
    ref.watch(terminalRuntimeExitCoordinatorProvider);
    ref.watch(workspaceActivityCoordinatorProvider);
    ref.watch(terminalRuntimeActiveWorkspaceCoordinatorProvider);
    ref.watch(workspaceActivityPersistenceCoordinatorProvider);
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
                      crossAxisAlignment: .stretch,
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
                          ),
                        ),
                        if (workspace != null && showContextSidebar)
                          WorkspaceContextSidebar(
                            workspace: workspace,
                            prefs: shell.viewPrefs,
                            sourceControlScope: sourceControlScope,
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
                            onSetGitDiffGroupMode:
                                controller.setGitDiffGroupMode,
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
                                  preview: true,
                                ),
                              );
                            },
                            onOpenFilePermanently: (relativePath) {
                              unawaited(
                                controller.openFileTab(
                                  workspace: workspace,
                                  relativePath: relativePath,
                                ),
                              );
                            },
                            onRevealInExplorer: (relativePath) {
                              controller.revealInExplorer(
                                workspace: workspace,
                                relativePath: relativePath,
                              );
                            },
                            onOpenGitDiff:
                                ({
                                  relativePath,
                                  area,
                                  gitDiffRoot,
                                  required scope,
                                  preview = false,
                                }) {
                                  return controller.openGitDiffTab(
                                    workspace: workspace,
                                    relativePath: relativePath,
                                    area: area,
                                    scope: scope,
                                    gitDiffRoot: gitDiffRoot,
                                    preview: preview,
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
                                  preview = false,
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
                                    preview: preview,
                                  );
                                },
                            onOpenSearchMatch: (target) {
                              unawaited(() async {
                                final tab = await controller.openEditorTab(
                                  workspace: workspace,
                                  relativePath: target.relativePath,
                                  preview: true,
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
                      mainAxisSize: .min,
                      children: <Widget>[
                        ResourceStatusBarControl(),
                        KeepAliveStatusBarControl(),
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
    return content;
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
    if (!mounted) return false;
    if (dirty.isNotEmpty) {
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
      if (confirmed != true) return false;
    }
    return true;
  }

  void _showError(String message) {
    AleraToast.show(context, message: message, tone: .error);
  }
}

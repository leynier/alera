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
    ref.watch(agentCanvasRuntimeSyncProvider);
    ref.watch(agentStatusNotificationCoordinatorProvider);
    ref.watch(agentAwakeCoordinatorProvider);
    ref.watch(keepAliveCoordinatorProvider);
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
    final terminalRuntime = ref.read(terminalRuntimeProvider);

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
                            browserTabsAvailable: browserTabsAvailable,
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
                            onFocusTerminal: (terminalSessionId) {
                              final tab = _workspaceTabByTerminalSession(
                                shell.tabs,
                                terminalSessionId,
                              );
                              if (tab == null) {
                                AleraToast.show(
                                  context,
                                  message: 'The Agent Canvas terminal is no longer open.',
                                  tone: .error,
                                );
                                return;
                              }
                              controller.setActiveTab(
                                workspaceId: workspace.id,
                                tabId: tab.id,
                              );
                              terminalRuntime
                                  .sessionFor(workspace: workspace, tab: tab)
                                  .requestFocus();
                            },
                            onOpenPullRequest: () {
                              controller.setContextPanelTab(.pullRequests);
                            },
                            onOpenArtifact: (artifactId) {
                              AleraToast.show(
                                context,
                                message:
                                    'Artifact $artifactId is registered for this Agent Canvas.',
                              );
                            },
                            onSourceControlAction: sourceControlScope == null
                                ? null
                                : (kind, action) async {
                                    await _runAgentCanvasSourceControlAction(
                                      ref: ref,
                                      workspace: workspace,
                                      sourceControlScope: sourceControlScope,
                                      kind: kind,
                                      action: action,
                                      terminalRuntime: terminalRuntime,
                                      controller: controller,
                                      tabs: shell.tabs,
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
    return BrowserNativeCallbackScope(child: content);
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
    AleraToast.show(context, message: message, tone: .error);
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

WorkspaceTabRecord? _workspaceTabByTerminalSession(
  List<WorkspaceTabRecord> tabs,
  String terminalSessionId,
) {
  for (final tab in tabs) {
    if (tab.kind == WorkspaceTabKind.terminal &&
        tab.terminalSessionId == terminalSessionId) {
      return tab;
    }
  }
  return null;
}

Future<void> _runAgentCanvasSourceControlAction({
  required WidgetRef ref,
  required Workspace workspace,
  required WorkspaceSourceControlScope sourceControlScope,
  required String kind,
  required Map<String, Object?> action,
  required TerminalRuntime terminalRuntime,
  required WorkbenchController controller,
  required List<WorkspaceTabRecord> tabs,
}) async {
  final sourceController = ref.read(
    workspaceSourceControlControllerProvider(sourceControlScope.path).notifier,
  );
  final rawPath = action['relativePath'];
  final sourceRelativePath = rawPath is String
      ? sourceControlScope.toSourceRelativePath(rawPath)
      : null;
  if (rawPath is String && sourceRelativePath == null) {
    throw StateError(
      'The action path is outside the active source control root.',
    );
  }
  switch (kind) {
    case 'stage':
      await sourceController.stage(sourceRelativePath);
    case 'unstage':
      await sourceController.unstage(sourceRelativePath);
    case 'discard':
      await sourceController.discard(sourceRelativePath);
    case 'commit':
      final message = action['message'];
      if (message is! String || message.trim().isEmpty) {
        throw StateError('A commit message is required.');
      }
      await sourceController.commit(message);
    case 'pull':
      await sourceController.pull();
    case 'push':
      await sourceController.push();
    case 'terminateTerminal':
      final terminalSessionId = action['terminalSessionId'];
      if (terminalSessionId is! String) {
        throw StateError('The terminal session id is required.');
      }
      final tab = _workspaceTabByTerminalSession(tabs, terminalSessionId);
      if (tab == null) {
        throw StateError('The Agent Canvas terminal is no longer open.');
      }
      // The controller disposes the terminal handle alongside the tab record.
      await controller.closeWorkspaceTab(workspace: workspace, tabId: tab.id);
    default:
      throw StateError(
        'This Agent Canvas action has no registered controller.',
      );
  }
}

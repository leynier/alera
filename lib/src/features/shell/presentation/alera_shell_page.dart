import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_shortcuts_scope.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_context_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraShellPage extends ConsumerWidget {
  const AleraShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(aleraDatabaseProvider);
    return dbAsync.when(
      loading: () => const _ShellLoading(),
      error: (error, _) => _ShellError(error: error.toString()),
      data: (_) => const _AleraShellPageBody(),
    );
  }
}

class _ShellLoading extends StatelessWidget {
  const _ShellLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ShellError extends StatelessWidget {
  const _ShellError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(AleraIcons.error, color: AleraTokens.error, size: 32),
              const SizedBox(height: AleraTokens.space12),
              Text(
                'Failed to open the local database',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AleraTokens.space8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AleraShellPageBody extends ConsumerStatefulWidget {
  const _AleraShellPageBody();

  @override
  ConsumerState<_AleraShellPageBody> createState() =>
      _AleraShellPageBodyState();
}

class _AleraShellPageBodyState extends ConsumerState<_AleraShellPageBody> {
  String? _lastErrorMessage;

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
    ref.watch(agentHookReceiverLifecycleCoordinatorProvider);
    ref.watch(agentHookInstallerCoordinatorProvider);
    ref.watch(agentStatusNotificationCoordinatorProvider);
    ref.watch(agentAwakeCoordinatorProvider);
    ref.watch(terminalRuntimeExitCoordinatorProvider);
    final state = ref.watch(workbenchControllerProvider);
    final error = state.error;
    if (error != null && error != _lastErrorMessage) {
      _lastErrorMessage = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showError(error);
      });
    }

    final project = state.activeProject;
    final workspace = state.activeWorkspace;
    final controller = ref.read(workbenchControllerProvider.notifier);

    return Scaffold(
      body: KeyboardShortcutsScope(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showContextSidebar =
                workspace != null &&
                _canShowContextSidebar(
                  shellWidth: constraints.maxWidth,
                  state: state,
                );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const ProjectWorkbenchSidebar(),
                Expanded(
                  child: _buildContent(
                    state: state,
                    project: project,
                    workspace: workspace,
                  ),
                ),
                if (workspace != null && showContextSidebar)
                  WorkspaceContextSidebar(
                    workspace: workspace,
                    prefs: state.viewPrefs,
                    sourceControlAvailable:
                        state.activeProject?.isGitRepository ?? false,
                    onToggleVisible: controller.toggleRightSidebarVisible,
                    onResize: controller.setRightSidebarWidth,
                    onSetContextPanelTab: controller.setContextPanelTab,
                    onSetExplorerMode: controller.setExplorerMode,
                    onSetGitDiffViewMode: controller.setGitDiffViewMode,
                    onOpenFile: (relativePath) {
                      unawaited(
                        controller.openFileTab(
                          workspace: workspace,
                          relativePath: relativePath,
                        ),
                      );
                    },
                    onOpenGitDiff: ({relativePath, area, required scope}) {
                      return controller.openGitDiffTab(
                        workspace: workspace,
                        relativePath: relativePath,
                        area: area,
                        scope: scope,
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
                    onPathMoved: (oldRelativePath, newRelativePath) async {
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
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent({
    required WorkbenchState state,
    required Project? project,
    required Workspace? workspace,
  }) {
    if (!state.bootstrapped && state.projects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.projects.isEmpty || project == null || workspace == null) {
      return const WelcomeDashboard();
    }
    final tabs = state.tabsFor(workspace.id);
    final controller = ref.read(workbenchControllerProvider.notifier);
    final terminalRuntime = ref.read(terminalRuntimeProvider);
    final agentStatuses = ref.watch(agentStatusControllerProvider);
    return WorkspaceWorkbenchView(
      project: project,
      workspace: workspace,
      tabs: tabs,
      layout: state.layoutFor(workspace.id),
      terminalRuntime: terminalRuntime,
      agentStatuses: agentStatuses,
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
      onOpenMarkdownViewerTab: ({required relativePath, targetGroupId}) async {
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
        terminalRuntime.closeTab(tabId);
        await controller.closeWorkspaceTab(workspace: workspace, tabId: tabId);
        ref.read(editorSessionRegistryProvider).forget(tabId);
      },
      onCloseTabs: (tabIds) async {
        if (!await _confirmCloseDirtyTabs(tabs, tabIds)) {
          return;
        }
        for (final tabId in tabIds) {
          terminalRuntime.closeTab(tabId);
        }
        await controller.closeWorkspaceTabs(
          workspace: workspace,
          tabIds: tabIds,
        );
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
          ({required tabId, required targetGroupId, required zone}) async {
            await controller.moveWorkspaceTab(
              workspaceId: workspace.id,
              tabId: tabId,
              targetGroupId: targetGroupId,
              zone: zone,
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

bool _canShowContextSidebar({
  required double shellWidth,
  required WorkbenchState state,
}) {
  final leftWidth = state.collapsed
      ? AleraTokens.sidebarCollapsedWidth
      : AleraTokens.sidebarDefaultWidth;
  final rightWidth = state.viewPrefs.rightSidebarVisible
      ? state.viewPrefs.rightSidebarWidth
      : AleraTokens.sidebarCollapsedWidth;
  return shellWidth - leftWidth - rightWidth >= AleraTokens.emptyStateMaxWidth;
}

String buildRawLogClipboardText(List<String> logs) {
  return logs.join('\n');
}

import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_shortcuts_scope.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
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
              const Icon(
                Icons.error_outline,
                color: AleraTokens.error,
                size: 32,
              ),
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

    return Scaffold(
      body: KeyboardShortcutsScope(
        child: Row(
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
          ],
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
    if (state.projects.isEmpty) {
      return AleraEmptyState(
        icon: Icons.folder_open,
        title: 'No projects yet',
        message: 'Add a project to create its main workspace.',
        action: FilledButton.icon(
          onPressed: _addProject,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('Add project'),
        ),
      );
    }
    if (project == null || workspace == null) {
      return const AleraEmptyState(
        icon: Icons.terminal,
        title: 'No workspace selected',
        message:
            'Select a workspace from the sidebar to open its terminal tabs.',
      );
    }
    final tabs = state.tabsFor(workspace.id);
    final controller = ref.read(workbenchControllerProvider.notifier);
    final terminalRuntime = ref.read(terminalRuntimeProvider);
    return WorkspaceWorkbenchView(
      project: project,
      workspace: workspace,
      tabs: tabs,
      layout: state.layoutFor(workspace.id),
      terminalRuntime: terminalRuntime,
      onCreateTab: ({targetGroupId}) async {
        await controller.createTerminalTab(
          workspace,
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
        terminalRuntime.closeTab(tabId);
        await controller.closeWorkspaceTab(workspace: workspace, tabId: tabId);
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
        await controller.splitWorkbenchGroupWithTerminal(
          workspace: workspace,
          groupId: groupId,
          zone: zone,
        );
      },
      onMergeGroup: ({required groupId}) async {
        await controller.mergeWorkbenchGroupIntoSibling(
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

  Future<void> _addProject() async {
    final result = await showDialog<AddProjectResult>(
      context: context,
      builder: (_) => const AddProjectDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    try {
      switch (result) {
        case AddLocalProjectResult():
          await controller.addLocalProject(
            path: result.path,
            name: result.name,
          );
          if (!mounted) {
            return;
          }
          _showSuccess('Project added');
        case CloneProjectResult():
          await _runWithProgress(
            message: 'Cloning repository…',
            action: () => controller.cloneProject(
              gitUrl: result.gitUrl,
              destinationPath: result.destinationPath,
              name: result.name,
            ),
          );
          if (!mounted) {
            return;
          }
          _showSuccess('Project cloned');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    }
  }

  Future<T> _runWithProgress<T>({
    required String message,
    required Future<T> Function() action,
  }) async {
    var progressOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AddProjectProgressDialog(message: message),
      ).whenComplete(() => progressOpen = false),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      return await action();
    } finally {
      if (mounted && progressOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  void _showSuccess(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.success);
  }

  void _showError(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.error);
  }
}

String buildRawLogClipboardText(List<String> logs) {
  return logs.join('\n');
}

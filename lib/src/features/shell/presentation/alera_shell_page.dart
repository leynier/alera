import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_shortcuts_scope.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
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
    ref.watch(terminalHostWarmupProvider);
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
    if (state.projects.isEmpty || project == null || workspace == null) {
      return const WelcomeDashboard();
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
        final tab = await controller.createTerminalTab(
          workspace,
          targetGroupId: targetGroupId,
        );
        terminalRuntime
            .sessionFor(workspace: workspace, tab: tab)
            .requestFocus();
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
      onCloseTabs: (tabIds) async {
        for (final tabId in tabIds) {
          terminalRuntime.closeTab(tabId);
        }
        await controller.closeWorkspaceTabs(
          workspace: workspace,
          tabIds: tabIds,
        );
      },
      onRenameTab: ({required tabId, required title}) async {
        await controller.renameWorkspaceTab(tabId: tabId, title: title);
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
      onUpdateSplitRatio: ({required nodePath, required ratio}) {
        controller.updateWorkbenchSplitRatio(
          workspaceId: workspace.id,
          nodePath: nodePath,
          ratio: ratio,
        );
      },
    );
  }

  void _showError(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.error);
  }
}

String buildRawLogClipboardText(List<String> logs) {
  return logs.join('\n');
}

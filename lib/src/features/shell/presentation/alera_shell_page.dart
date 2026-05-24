import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/workbench_status_bar.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
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
    final activeTab = state.activeTerminalTab;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ProjectWorkbenchSidebar(),
          Expanded(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: _buildContent(
                    state: state,
                    project: project,
                    workspace: workspace,
                  ),
                ),
                WorkbenchStatusBar(
                  workspace: workspace,
                  activeTab: activeTab,
                  tabCount: workspace == null
                      ? 0
                      : state.tabsFor(workspace.id).length,
                ),
              ],
            ),
          ),
        ],
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
    if (project == null || workspace == null) {
      return _EmptyState(
        icon: Icons.terminal,
        title: 'Pick a workspace',
        message:
            'Select an existing workspace from the sidebar, or add a project to create the main workspace.',
        actionLabel: 'Add project',
        onAction: _addProject,
      );
    }
    final tabs = state.tabsFor(workspace.id);
    final controller = ref.read(workbenchControllerProvider.notifier);
    final terminalRuntime = ref.read(terminalRuntimeProvider);
    return WorkspaceWorkbenchView(
      project: project,
      workspace: workspace,
      tabs: tabs,
      activeTab: state.activeTerminalTab,
      terminalRuntime: terminalRuntime,
      onCreateTab: () async {
        await controller.createTerminalTab(workspace);
      },
      onSelectTab: (tabId) =>
          controller.setActiveTab(workspaceId: workspace.id, tabId: tabId),
      onCloseTab: (tabId) async {
        terminalRuntime.closeTab(tabId);
        await controller.closeTerminalTab(workspace: workspace, tabId: tabId);
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
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .addProject(repoPath: result.repoPath, name: result.name);
      if (!mounted) {
        return;
      }
      _showSuccess('Project added');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    }
  }

  void _showSuccess(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.success);
  }

  void _showError(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.error);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                  border: Border.all(color: AleraTokens.border),
                ),
                child: Icon(icon, size: 28, color: AleraTokens.foregroundMuted),
              ),
              const SizedBox(height: AleraTokens.space20),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AleraTokens.space8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              if (actionLabel != null &&
                  actionLabel!.trim().isNotEmpty &&
                  onAction != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space24),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(actionLabel!),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(170, 34),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String buildRawLogClipboardText(List<String> logs) {
  return logs.join('\n');
}

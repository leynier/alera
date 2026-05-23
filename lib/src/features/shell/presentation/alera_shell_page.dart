import 'dart:io';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agents/acp/presentation/acp_playground_page.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/projects/presentation/project_sidebar.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/features/shell/presentation/alera_status_bar.dart';
import 'package:alera/src/features/shell/presentation/alera_top_bar.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

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
  bool _rawLogExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(sessionControllerProvider.notifier).bootstrap();
      await ref.read(projectsControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(sessionControllerProvider.notifier);
    final error = ref.watch(sessionControllerProvider.select((s) => s.error));

    if (error != null && error != _lastErrorMessage) {
      _lastErrorMessage = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showError(error);
      });
    }

    final workspacePath = ref.watch(
      sessionControllerProvider.select((s) => s.selectedWorkspacePath),
    );
    final statusBarWorkspacePath = ref.watch(
      sessionControllerProvider.select(
        (s) => s.activeSession?.workspacePath ?? s.selectedWorkspacePath,
      ),
    );
    final activeSessionTitle = ref.watch(
      sessionControllerProvider.select((s) => s.activeSession?.title),
    );
    final isBusy = ref.watch(sessionControllerProvider.select((s) => s.isBusy));
    final activityLogEmpty = ref.watch(
      sessionControllerProvider.select((s) => s.activityLog.isEmpty),
    );

    final connectionState = ref.watch(
      sessionControllerProvider.select((s) => s.connectionState),
    );
    final runningTurnCount = ref.watch(
      sessionControllerProvider.select((s) => s.runningTurnCount),
    );
    final statusHeader = ref.watch(
      sessionControllerProvider.select((s) => s.statusHeader),
    );
    final lastTurnDiff = ref.watch(
      sessionControllerProvider.select((s) => s.lastTurnDiff),
    );

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ProjectSidebar(),
          Expanded(
            child: Column(
              children: <Widget>[
                AleraTopBar(
                  workspaceName: _workspaceName(workspacePath),
                  sessionTitle: activeSessionTitle,
                  isBusy: isBusy,
                  onOpenAcpPlayground: () => _openAcpPlayground(context),
                ),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, child) {
                      final state = ref.watch(sessionControllerProvider);
                      return _buildContent(
                        state: state,
                        controller: controller,
                      );
                    },
                  ),
                ),
                AleraStatusBar(
                  connectionState: connectionState,
                  runningTurnCount: runningTurnCount,
                  statusHeader: statusHeader,
                  lastTurnDiff: lastTurnDiff,
                  workspacePath: statusBarWorkspacePath,
                  rawLogExpanded: _rawLogExpanded,
                  onToggleRawLog: () =>
                      setState(() => _rawLogExpanded = !_rawLogExpanded),
                  onCopyRawLog: () =>
                      _copyRawLog(ref.read(sessionControllerProvider)),
                  canCopyRawLog: !activityLogEmpty,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent({
    required SessionState state,
    required SessionController controller,
  }) {
    final workspacePath = state.selectedWorkspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      return _EmptyState(
        icon: Icons.workspaces_outline,
        title: 'Pick a chat',
        message:
            'Select an existing chat from the sidebar, or add a project and start a new chat.',
        actionLabel: 'Add project',
        onAction: () => _addProject(context),
        statusHeader: state.statusHeader,
      );
    }
    return SessionWorkspaceView(
      state: state,
      onSendInput: controller.sendInput,
      onInterruptTurn: controller.interruptActiveTurn,
      isTurnRunning: state.runningTurnCount > 0,
      isInterrupting: state.isInterrupting,
      onModelChanged: controller.updateActiveSessionModel,
      activeReasoningEffort: state.activeReasoningEffort,
      supportedReasoningEfforts: supportedReasoningEffortsForModel(
        state.activeModelId,
      ),
      onReasoningEffortChanged: controller.updateReasoningEffort,
      activeSpeedMode: state.activeSpeedMode,
      onSpeedModeChanged: controller.updateSpeedMode,
      isMarkdownEnabled: state.activeMarkdownEnabled,
      onMarkdownModeChanged: controller.updateMarkdownEnabled,
      rawLogExpanded: _rawLogExpanded,
      onAddAttachment: () => _addAttachment(controller),
      onPasteImage: (file) => _pasteImage(controller, file),
      onRemoveAttachment: controller.removeAttachment,
      onRemoveFromQueue: controller.removeFromQueue,
      onSteerQueuedMessage: controller.steerQueuedMessage,
      onStartEditingPendingMessage: controller.startEditingPendingMessage,
      onUpdatePendingMessage: controller.updatePendingMessage,
      onDeletePendingMessage: controller.removeFromQueue,
      onFinishEditingPendingMessage: controller.finishEditingPendingMessage,
      onPlanModeToggled: controller.togglePlanMode,
      onImplementPlanPressed: controller.implementPlanFromChatAction,
      onPermissionModeToggled: controller.togglePermissionMode,
      onPermissionModeSelected: controller.setPermissionMode,
      onApproveRequest: controller.approveRequest,
      onDeclineRequest: controller.declineRequest,
      onSubmitUserInput: controller.submitUserInput,
      onDismissUserInput: controller.dismissUserInput,
      onListSkills: controller.listAvailableSkills,
      onListApps: controller.listAvailableApps,
      onListReviewBranches: controller.listReviewBranches,
      onAddDraftItem: controller.addComposerDraftItem,
      onRemoveDraftItem: controller.removeComposerDraftItem,
      onStartReviewFromPreset: controller.startReviewFromPreset,
      onCompact: controller.compactContext,
    );
  }

  Future<void> _addAttachment(SessionController controller) async {
    final XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[const XTypeGroup(label: 'All files')],
      );
    } catch (_) {
      return;
    }
    if (file == null) {
      return;
    }
    final kind = _attachmentKindFromPath(file.path);
    final mimeType = kind == AttachmentKind.image
        ? _imageMimeType(file.path)
        : null;
    controller.addAttachment(
      ComposerAttachment(
        id: const Uuid().v4(),
        kind: kind,
        path: file.path,
        displayName: file.name,
        mimeType: mimeType,
      ),
    );
  }

  void _pasteImage(SessionController controller, File file) {
    controller.addAttachment(
      ComposerAttachment(
        id: const Uuid().v4(),
        kind: AttachmentKind.image,
        path: file.path,
        displayName: p.basename(file.path),
        mimeType: 'image/png',
      ),
    );
  }

  AttachmentKind _attachmentKindFromPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (const <String>{'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext)) {
      return AttachmentKind.image;
    }
    return AttachmentKind.file;
  }

  String _imageMimeType(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png';
    }
  }

  Future<void> _addProject(BuildContext context) async {
    final result = await showDialog<AddProjectResult>(
      context: context,
      builder: (_) => const AddProjectDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(projectsControllerProvider.notifier)
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

  void _openAcpPlayground(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AcpPlaygroundPage()));
  }

  String? _workspaceName(String? workspacePath) {
    if (workspacePath == null || workspacePath.isEmpty) {
      return null;
    }
    final name = p.basename(workspacePath);
    if (name.isEmpty) {
      return workspacePath;
    }
    return name;
  }

  void _showSuccess(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.success);
  }

  void _showError(String message) {
    AleraToast.show(context, message: message, tone: AleraToastTone.error);
  }

  Future<void> _copyRawLog(SessionState state) async {
    if (state.activityLog.isEmpty) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'No logs to copy',
        tone: AleraToastTone.error,
      );
      return;
    }

    final text = buildRawLogClipboardText(state.activityLog);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Raw logs copied',
        tone: AleraToastTone.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Failed to copy raw logs',
        tone: AleraToastTone.error,
      );
    }
  }
}

String buildRawLogClipboardText(List<String> logs) {
  return logs.join('\n');
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.statusHeader,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? statusHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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

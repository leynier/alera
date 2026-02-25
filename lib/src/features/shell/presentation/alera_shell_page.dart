import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/features/shell/presentation/alera_status_bar.dart';
import 'package:alera/src/features/shell/presentation/alera_top_bar.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class AleraShellPage extends ConsumerStatefulWidget {
  const AleraShellPage({super.key});

  @override
  ConsumerState<AleraShellPage> createState() => _AleraShellPageState();
}

class _AleraShellPageState extends ConsumerState<AleraShellPage> {
  String? _lastErrorMessage;
  bool _rawLogExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(sessionControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);

    if (state.error != null && state.error != _lastErrorMessage) {
      _lastErrorMessage = state.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showError(state.error!);
      });
    }

    return Scaffold(
      body: Column(
        children: <Widget>[
          AleraTopBar(
            workspaceName: _workspaceName(state.selectedWorkspacePath),
            sessionTitle: state.activeSession?.title,
            isBusy: state.isBusy,
            onSelectWorkspace: () => _selectWorkspace(controller),
          ),
          Expanded(
            child: _buildContent(state: state, controller: controller),
          ),
          AleraStatusBar(
            state: state,
            rawLogExpanded: _rawLogExpanded,
            onToggleRawLog: () =>
                setState(() => _rawLogExpanded = !_rawLogExpanded),
            onCopyRawLog: () => _copyRawLog(state),
            canCopyRawLog: state.activityLog.isNotEmpty,
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
        icon: Icons.folder_open_outlined,
        title: 'Select a repository folder',
        message: 'Choose a git repository folder to start working.',
        actionLabel: 'Select folder',
        onAction: () => _selectWorkspace(controller),
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
      isMarkdownEnabled: state.activeMarkdownEnabled,
      onMarkdownModeChanged: controller.updateMarkdownEnabled,
      rawLogExpanded: _rawLogExpanded,
      onAddAttachment: () => _addAttachment(controller),
      onRemoveAttachment: controller.removeAttachment,
      onRemoveFromQueue: controller.removeFromQueue,
      onPlanModeToggled: controller.togglePlanMode,
      onPermissionModeToggled: controller.togglePermissionMode,
      onApproveRequest: controller.approveRequest,
      onDeclineRequest: controller.declineRequest,
      onSubmitUserInput: controller.submitUserInput,
      onDismissUserInput: controller.dismissUserInput,
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

  Future<void> _selectWorkspace(SessionController controller) async {
    final path = await _showWorkspaceDialog();
    if (path == null || path.trim().isEmpty) {
      return;
    }

    final ok = await controller.selectWorkspaceFromPath(path.trim());
    if (!mounted) {
      return;
    }
    if (!ok) {
      final latestState = ref.read(sessionControllerProvider);
      final message = latestState.error ?? 'Failed to select folder';
      _showError(message);
      return;
    }
    _showSuccess('Workspace selected');
  }

  Future<String?> _showWorkspaceDialog() {
    return showDialog<String>(
      context: context,
      builder: (context) => const _SelectWorkspaceDialog(),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            const Icon(
              Icons.check_circle_outline,
              size: 16,
              color: AleraTokens.success,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            const Icon(Icons.error_outline, size: 16, color: AleraTokens.error),
            const SizedBox(width: AleraTokens.space8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _copyRawLog(SessionState state) async {
    if (state.activityLog.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No logs to copy')));
      return;
    }

    final text = buildRawLogClipboardText(state.activityLog);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Raw logs copied')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to copy raw logs')));
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
              if (actionLabel != null && onAction != null) ...<Widget>[
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

class _SelectWorkspaceDialog extends StatefulWidget {
  const _SelectWorkspaceDialog();

  @override
  State<_SelectWorkspaceDialog> createState() => _SelectWorkspaceDialogState();
}

class _SelectWorkspaceDialogState extends State<_SelectWorkspaceDialog> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_pathController.text.trim());
  }

  Future<void> _browse() async {
    try {
      final selected = await getDirectoryPath(
        confirmButtonText: 'Select repository',
      );
      if (!mounted || selected == null || selected.trim().isEmpty) {
        return;
      }
      _pathController.text = selected.trim();
      _pathController.selection = TextSelection.fromPosition(
        TextPosition(offset: _pathController.text.length),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Native folder picker is not available; paste path manually.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(
            Icons.folder_special_outlined,
            size: 18,
            color: AleraTokens.accent,
          ),
          const SizedBox(width: AleraTokens.space8),
          Text('Select folder', style: theme.textTheme.titleLarge),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Choose the git repository you want to work on',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AleraTokens.space16),
            TextField(
              controller: _pathController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Repository path',
                hintText: '/path/to/git/repository',
                suffixIcon: Tooltip(
                  message: 'Browse',
                  child: IconButton(
                    onPressed: _browse,
                    mouseCursor: SystemMouseCursors.click,
                    icon: const Icon(Icons.folder_open, size: 18),
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Use folder')),
      ],
    );
  }
}

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/presentation/chat_starter_view.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/features/shell/presentation/alera_status_bar.dart';
import 'package:alera/src/features/shell/presentation/alera_top_bar.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class AleraShellPage extends ConsumerStatefulWidget {
  const AleraShellPage({super.key});

  @override
  ConsumerState<AleraShellPage> createState() => _AleraShellPageState();
}

class _AleraShellPageState extends ConsumerState<AleraShellPage> {
  String? _lastErrorMessage;

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
          AleraStatusBar(state: state),
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
        title: 'select a repository folder',
        message: 'choose a git repository folder to start working.',
        actionLabel: 'select folder',
        onAction: () => _selectWorkspace(controller),
      );
    }
    final activeSession = state.activeSession;
    if (activeSession == null) {
      return ChatStarterView(
        workspacePath: workspacePath,
        controller: controller,
        isBusy: state.isBusy,
        availableModels: state.availableModels,
      );
    }
    return SessionWorkspaceView(state: state, controller: controller);
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
      final message = latestState.error ?? 'failed to select folder';
      _showError(message);
      return;
    }
    _showSuccess('workspace selected');
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
                    minimumSize: const Size(170, 40),
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
        confirmButtonText: 'select repository',
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
            'native folder picker is not available; paste path manually.',
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
          Text('select folder', style: theme.textTheme.titleLarge),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'choose the git repository you want to work on',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AleraTokens.space16),
            TextField(
              controller: _pathController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'repository path',
                hintText: '/path/to/git/repository',
                suffixIcon: Tooltip(
                  message: 'browse',
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
          child: const Text('cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('use folder')),
      ],
    );
  }
}

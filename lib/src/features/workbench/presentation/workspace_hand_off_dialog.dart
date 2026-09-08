import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

class const WorkspaceHandOffRequest({
  required final String branch,
  required final bool reuseExistingBranch,
  final String? name,
});

Future<WorkspaceHandOffRequest?> showWorkspaceHandOffDialog({
  required BuildContext context,
  required String currentBranch,
}) {
  return showDialog<WorkspaceHandOffRequest>(
    context: context,
    builder: (_) => _WorkspaceHandOffDialog(currentBranch: currentBranch),
  );
}

class const _WorkspaceHandOffDialog({required final String currentBranch})
    extends StatefulWidget {
  @override
  State<_WorkspaceHandOffDialog> createState() =>
      _WorkspaceHandOffDialogState();
}

class _WorkspaceHandOffDialogState extends State<_WorkspaceHandOffDialog> {
  late final TextEditingController _branchController;
  late final TextEditingController _nameController;
  String? _branchError;

  bool get _currentIsDefault {
    final current = widget.currentBranch.trim();
    return current == 'main' || current == 'master' || current == 'HEAD';
  }

  @override
  void initState() {
    super.initState();
    _branchController = TextEditingController(
      text: _currentIsDefault ? '' : widget.currentBranch,
    );
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _branchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final branch = _branchController.text.trim();
    if (branch.isEmpty) {
      setState(() => _branchError = 'Branch name is required');
      return;
    }
    final name = _nameController.text.trim();
    Navigator.of(context).pop(
      WorkspaceHandOffRequest(
        branch: branch,
        reuseExistingBranch: branch == widget.currentBranch.trim(),
        name: name.isEmpty ? null : name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Text('Hand Off', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Text(
              'Moves uncommitted changes from the main worktree into a new child workspace. Use the current branch name to move that branch, or enter a new name.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraTextField(
              controller: _branchController,
              autofocus: true,
              labelText: 'Branch Name *',
              hintText: _currentIsDefault
                  ? 'e.g. feat/isolated-change'
                  : widget.currentBranch,
              errorText: _branchError,
              onChanged: (_) {
                if (_branchError != null) {
                  setState(() => _branchError = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _nameController,
              labelText: 'Workspace Name',
              hintText: 'Defaults to the branch name',
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(onPressed: _submit, child: const Text('Hand Off')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

import 'dart:async';

class const WorkspaceHandOffRequest({
  required final String branch,
  required final bool reuseExistingBranch,
  final String? name,
});

Future<WorkspaceHandOffRequest?> showWorkspaceHandOffDialog({
  required BuildContext context,
  required String currentBranch,
  String? defaultBranch,
  Future<String> Function()? generateBranch,
  Future<String?> Function(String branch)? validateBranch,
  Future<void> Function()? cancelGeneration,
}) {
  return showDialog<WorkspaceHandOffRequest>(
    context: context,
    builder: (_) => _WorkspaceHandOffDialog(
      currentBranch: currentBranch,
      defaultBranch: defaultBranch,
      generateBranch: generateBranch,
      validateBranch: validateBranch,
      cancelGeneration: cancelGeneration,
    ),
  );
}

class const _WorkspaceHandOffDialog({
  required final String currentBranch,
  final String? defaultBranch,
  final Future<String> Function()? generateBranch,
  final Future<String?> Function(String branch)? validateBranch,
  final Future<void> Function()? cancelGeneration,
}) extends StatefulWidget {
  @override
  State<_WorkspaceHandOffDialog> createState() =>
      _WorkspaceHandOffDialogState();
}

class _WorkspaceHandOffDialogState extends State<_WorkspaceHandOffDialog> {
  late final TextEditingController _branchController;
  late final TextEditingController _nameController;
  String? _branchError;
  bool _generating = false;
  bool _validating = false;
  int _editRevision = 0;
  int _generation = 0;

  bool get _currentIsDefault {
    final current = widget.currentBranch.trim();
    return widget.defaultBranch == null ||
        current == widget.defaultBranch ||
        current == 'HEAD';
  }

  @override
  void initState() {
    super.initState();
    _branchController = TextEditingController(
      text: _currentIsDefault ? '' : widget.currentBranch,
    );
    _nameController = TextEditingController();
    if (_currentIsDefault && widget.generateBranch != null) {
      _generate();
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(widget.cancelGeneration?.call().catchError((Object _) {}));
    _branchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final generate = widget.generateBranch;
    if (generate == null) return;
    final generation = ++_generation;
    final revision = _editRevision;
    setState(() {
      _generating = true;
      _branchError = null;
    });
    try {
      await widget.cancelGeneration?.call();
      if (!mounted || generation != _generation) return;
      final branch = await generate();
      if (!mounted || generation != _generation || revision != _editRevision) {
        return;
      }
      _branchController.text = branch;
      _editRevision++;
    } catch (error) {
      if (mounted && generation == _generation && revision == _editRevision) {
        setState(
          () => _branchError =
              'AI Assist failed. Enter a branch name or regenerate. $error',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _generating = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_validating) return;
    final branch = _branchController.text.trim();
    if (branch.isEmpty) {
      setState(() => _branchError = 'Branch name is required');
      return;
    }
    if (_currentIsDefault && branch == widget.currentBranch.trim()) {
      setState(
        () => _branchError = 'Choose a new branch name for the default branch',
      );
      return;
    }
    final revision = _editRevision;
    setState(() => _validating = true);
    try {
      final error = await widget.validateBranch?.call(branch);
      if (!mounted || revision != _editRevision) return;
      if (error != null) {
        setState(() => _branchError = error);
        return;
      }
    } catch (error) {
      if (mounted) setState(() => _branchError = error.toString());
      return;
    } finally {
      if (mounted) setState(() => _validating = false);
    }
    if (!mounted) return;
    _generation++;
    unawaited(widget.cancelGeneration?.call().catchError((Object _) {}));
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
                _editRevision++;
                if (_branchError != null) {
                  setState(() => _branchError = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            if (widget.generateBranch != null)
              TextButton(
                onPressed: _generating ? null : _generate,
                child: Text(
                  _generating
                      ? 'Generating branch name...'
                      : 'Regenerate Branch Name',
                ),
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
                FilledButton(
                  onPressed: _validating ? null : _submit,
                  child: const Text('Hand Off'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

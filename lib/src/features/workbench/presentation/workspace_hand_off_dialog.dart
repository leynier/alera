import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

import 'dart:async';

class const WorkspaceHandOffRequest({
  required final String branch,
  required final bool reuseExistingBranch,
  required final bool moveChanges,
  final String? replacementBranch,
  final String? name,
});

Future<WorkspaceHandOffRequest?> showWorkspaceHandOffDialog({
  required BuildContext context,
  required String currentBranch,
  String? defaultBranch,
  String? branchContextNotice,
  Future<String> Function()? generateBranch,
  Future<String?> Function(String branch)? validateBranch,
  Future<String?> Function(String branch)? validateReplacementBranch,
  Future<void> Function()? cancelGeneration,
}) {
  return showDialog<WorkspaceHandOffRequest>(
    context: context,
    builder: (_) => _WorkspaceHandOffDialog(
      currentBranch: currentBranch,
      defaultBranch: defaultBranch,
      branchContextNotice: branchContextNotice,
      generateBranch: generateBranch,
      validateBranch: validateBranch,
      validateReplacementBranch: validateReplacementBranch,
      cancelGeneration: cancelGeneration,
    ),
  );
}

class const _WorkspaceHandOffDialog({
  required final String currentBranch,
  final String? defaultBranch,
  final String? branchContextNotice,
  final Future<String> Function()? generateBranch,
  final Future<String?> Function(String branch)? validateBranch,
  final Future<String?> Function(String branch)? validateReplacementBranch,
  final Future<void> Function()? cancelGeneration,
}) extends StatefulWidget {
  @override
  State<_WorkspaceHandOffDialog> createState() =>
      _WorkspaceHandOffDialogState();
}

class _WorkspaceHandOffDialogState extends State<_WorkspaceHandOffDialog> {
  late final TextEditingController _branchController;
  late final TextEditingController _replacementController;
  bool _moveChanges = false;
  bool _confirmed = false;
  String? _branchError;
  bool _generating = false;
  bool _validating = false;
  int _editRevision = 0;
  int _generation = 0;

  bool get _movingCurrentBranch =>
      _branchController.text.trim() == widget.currentBranch.trim();

  @override
  void initState() {
    super.initState();
    _branchController = TextEditingController();
    _replacementController = TextEditingController();
    if (widget.generateBranch != null) {
      _generate();
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(widget.cancelGeneration?.call().catchError((Object _) {}));
    _branchController.dispose();
    _replacementController.dispose();
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
      _confirmed = false;
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
    if (_validating || !_confirmed) return;
    final branch = _branchController.text.trim();
    if (branch.isEmpty) {
      setState(() => _branchError = 'Branch name is required');
      return;
    }
    final replacement = _replacementController.text.trim();
    if (_movingCurrentBranch &&
        (replacement.isEmpty || replacement == branch)) {
      setState(
        () => _branchError =
            'Choose a different existing branch for the project folder',
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
      if (_movingCurrentBranch) {
        final replacementError = await widget.validateReplacementBranch?.call(
          replacement,
        );
        if (!mounted || revision != _editRevision) return;
        if (replacementError != null) {
          setState(() => _branchError = replacementError);
          return;
        }
      }
    } catch (error) {
      if (mounted) setState(() => _branchError = error.toString());
      return;
    } finally {
      if (mounted) setState(() => _validating = false);
    }
    if (!mounted || !_confirmed || revision != _editRevision) return;
    _generation++;
    unawaited(widget.cancelGeneration?.call().catchError((Object _) {}));
    Navigator.of(context).pop(
      WorkspaceHandOffRequest(
        branch: branch,
        reuseExistingBranch: branch == widget.currentBranch.trim(),
        moveChanges: _movingCurrentBranch || _moveChanges,
        replacementBranch: _movingCurrentBranch ? replacement : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              Text('Hand Off', style: theme.textTheme.titleMedium),
              const SizedBox(height: AleraTokens.space12),
              Text(
                'Moves this task to a new worktree while keeping its name, tabs and identity. A new branch leaves the project folder on its current branch. Moving the current branch requires a replacement. Stop this task’s processes before continuing.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              if (widget.branchContextNotice case final String notice) ...[
                const SizedBox(height: AleraTokens.space12),
                Text(notice, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: AleraTokens.space16),
              AleraTextField(
                controller: _branchController,
                autofocus: true,
                labelText: 'Branch Name *',
                hintText: 'New branch, or ${widget.currentBranch} to move it',
                errorText: _branchError,
                onChanged: (_) {
                  setState(() {
                    _editRevision++;
                    _branchError = null;
                    _confirmed = false;
                  });
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
              if (_movingCurrentBranch) ...[
                AleraTextField(
                  controller: _replacementController,
                  labelText: 'Replacement Branch *',
                  hintText:
                      'Existing branch, e.g. ${widget.defaultBranch ?? 'main'}',
                  onChanged: (_) => setState(() {
                    _editRevision++;
                    _confirmed = false;
                  }),
                ),
                const SizedBox(height: AleraTokens.space12),
                const Text(
                  'All transferable uncommitted changes move with the current branch.',
                ),
              ] else
                AleraSegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Leave Changes')),
                    ButtonSegment(value: true, label: Text('Move All Changes')),
                  ],
                  selected: _moveChanges,
                  onSelectionChanged: (value) => setState(() {
                    _moveChanges = value;
                    _editRevision++;
                    _confirmed = false;
                  }),
                ),
              const SizedBox(height: AleraTokens.space12),
              const Text(
                'Moving changes removes them from the shared folder. Changing its branch affects every task using that folder.',
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraCheckbox(
                value: _confirmed,
                label: 'Confirm Shared Impact',
                onChanged: (value) => setState(() => _confirmed = value),
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
                    onPressed: _validating || !_confirmed ? null : _submit,
                    child: const Text('Hand Off'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

class CreateWorkspaceResult {
  const CreateWorkspaceResult({
    required this.sourceBranch,
    required this.newBranchName,
    this.name,
  });

  final String sourceBranch;
  final String newBranchName;
  final String? name;
}

class CreateWorkspaceDialog extends StatefulWidget {
  const CreateWorkspaceDialog({
    super.key,
    required this.project,
    required this.branches,
  });

  final Project project;
  final List<String> branches;

  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<CreateWorkspaceDialog> {
  final TextEditingController _sourceBranchController = TextEditingController();
  final TextEditingController _newBranchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String? _selectedSourceBranch;
  bool _nameTouched = false;
  String? _sourceBranchError;
  String? _newBranchError;

  @override
  void initState() {
    super.initState();
    final defaultBranch = _pickDefaultSourceBranch(widget.branches);
    _selectedSourceBranch = defaultBranch;
    if (defaultBranch != null) {
      _sourceBranchController.text = defaultBranch;
    }
  }

  @override
  void dispose() {
    _sourceBranchController.dispose();
    _newBranchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String? _pickDefaultSourceBranch(List<String> branches) {
    for (final preferred in const <String>[
      'main',
      'origin/main',
      'master',
      'origin/master',
    ]) {
      if (branches.contains(preferred)) {
        return preferred;
      }
    }
    if (branches.isEmpty) {
      return null;
    }
    return branches.first;
  }

  void _submit() {
    final sourceBranch = (_selectedSourceBranch ?? _sourceBranchController.text)
        .trim();
    final newBranchName = _newBranchController.text.trim();
    final name = _nameController.text.trim();
    final sourceBranchError = sourceBranch.isEmpty
        ? 'Source branch is required'
        : null;
    final newBranchError = newBranchName.isEmpty
        ? 'New branch name is required'
        : null;
    if (sourceBranchError != null || newBranchError != null) {
      setState(() {
        _sourceBranchError = sourceBranchError;
        _newBranchError = newBranchError;
      });
      return;
    }
    Navigator.of(context).pop(
      CreateWorkspaceResult(
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        name: name.isEmpty ? null : name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.account_tree_outlined, color: AleraTokens.accent),
          const SizedBox(width: AleraTokens.space8),
          Text('New workspace', style: theme.textTheme.titleLarge),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Project: ${widget.project.name}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            if (widget.branches.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedSourceBranch,
                decoration: InputDecoration(
                  labelText: 'Source branch',
                  errorText: _sourceBranchError,
                ),
                items: <DropdownMenuItem<String>>[
                  for (final branch in widget.branches)
                    DropdownMenuItem<String>(
                      value: branch,
                      child: Text(branch),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedSourceBranch = value;
                    _sourceBranchError = null;
                  });
                },
              )
            else
              TextField(
                controller: _sourceBranchController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Source branch',
                  hintText: 'e.g. main',
                  errorText: _sourceBranchError,
                ),
                onChanged: (_) {
                  setState(() => _sourceBranchError = null);
                },
                onSubmitted: (_) => _submit(),
              ),
            const SizedBox(height: AleraTokens.space12),
            TextField(
              controller: _newBranchController,
              autofocus: widget.branches.isNotEmpty,
              decoration: InputDecoration(
                labelText: 'New branch name',
                hintText: 'e.g. feature/terminal-tabs',
                errorText: _newBranchError,
              ),
              onChanged: (value) {
                if (!_nameTouched) {
                  _nameController.text = value.trim();
                }
                setState(() => _newBranchError = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Workspace name (optional)',
              ),
              onChanged: (_) => _nameTouched = true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space12),
            Container(
              padding: const EdgeInsets.all(AleraTokens.space12),
              decoration: BoxDecoration(
                color: AleraTokens.surfaceVariant,
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: Text(
                'Alera will create a new git worktree from the selected source branch and open it as a workspace with its own terminal tabs.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create workspace')),
      ],
    );
  }
}

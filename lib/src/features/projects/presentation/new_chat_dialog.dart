import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class NewChatResult {
  const NewChatResult({
    required this.useNewWorktree,
    this.worktreeName,
    this.title,
  });

  final bool useNewWorktree;
  final String? worktreeName;
  final String? title;
}

class NewChatDialog extends StatefulWidget {
  const NewChatDialog({
    super.key,
    required this.project,
    required this.existingWorktreeNames,
  });

  final Project project;
  final Set<String> existingWorktreeNames;

  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  final TextEditingController _worktreeNameController = TextEditingController();
  bool _useWorktree = false;
  String? _worktreeError;

  static final RegExp _slugAllowed = RegExp(r'^[a-z0-9-]+$');

  @override
  void dispose() {
    _worktreeNameController.dispose();
    super.dispose();
  }

  String? _validateSlug(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return 'Name is required';
    }
    if (!_slugAllowed.hasMatch(value)) {
      return 'Use lowercase letters, digits, and dashes only';
    }
    if (widget.existingWorktreeNames.contains(value)) {
      return 'A worktree with this name already exists';
    }
    return null;
  }

  void _submit() {
    if (_useWorktree) {
      final name = _worktreeNameController.text.trim();
      final error = _validateSlug(name);
      if (error != null) {
        setState(() => _worktreeError = error);
        return;
      }
      Navigator.of(
        context,
      ).pop(NewChatResult(useNewWorktree: true, worktreeName: name));
      return;
    }
    Navigator.of(context).pop(const NewChatResult(useNewWorktree: false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worktreeName = _worktreeNameController.text.trim();
    final repoBase =
        '~/.alera/worktrees/${p.basename(widget.project.repoPath)}';
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(
            Icons.chat_bubble_outline,
            size: 18,
            color: AleraTokens.accent,
          ),
          const SizedBox(width: AleraTokens.space8),
          Text('New chat', style: theme.textTheme.titleLarge),
        ],
      ),
      content: SizedBox(
        width: 520,
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
            _OptionTile(
              selected: !_useWorktree,
              title: 'Use main repo',
              description:
                  'Run on ${widget.project.repoPath}\nKeeps the current branch.',
              onTap: () => setState(() {
                _useWorktree = false;
                _worktreeError = null;
              }),
            ),
            const SizedBox(height: AleraTokens.space8),
            _OptionTile(
              selected: _useWorktree,
              title: 'New worktree',
              description:
                  'Creates an isolated `git worktree` so this chat works on its own branch without touching the main checkout.',
              onTap: () => setState(() => _useWorktree = true),
            ),
            if (_useWorktree) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              TextField(
                controller: _worktreeNameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Worktree name',
                  hintText: 'e.g. feature-auth',
                  errorText: _worktreeError,
                ),
                onChanged: (_) {
                  setState(() {
                    _worktreeError = null;
                  });
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AleraTokens.space8),
              Container(
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceVariant,
                  border: Border.all(color: AleraTokens.borderSubtle),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Path: $repoBase/${worktreeName.isEmpty ? "<name>" : worktreeName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space4),
                    Text(
                      'Branch: alera/${worktreeName.isEmpty ? "<name>" : worktreeName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create chat')),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AleraTokens.space12),
        decoration: BoxDecoration(
          color: selected ? AleraTokens.surfaceElevated : AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          border: Border.all(
            color: selected ? AleraTokens.accent : AleraTokens.borderSubtle,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected
                  ? AleraTokens.accent
                  : AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

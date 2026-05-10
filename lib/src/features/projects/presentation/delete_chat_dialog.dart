import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:flutter/material.dart';

enum DeleteChatAction { cancel, keepWorktree, deleteWorktree }

class DeleteChatDialog extends StatelessWidget {
  const DeleteChatDialog({
    super.key,
    required this.chatTitle,
    required this.worktree,
  });

  final String chatTitle;
  final Worktree? worktree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wt = worktree;
    if (wt == null) {
      return AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'This permanently removes "$chatTitle" and its persisted history.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(DeleteChatAction.cancel),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(DeleteChatAction.keepWorktree),
            style: FilledButton.styleFrom(
              backgroundColor: AleraTokens.error,
              foregroundColor: AleraTokens.onError,
            ),
            child: const Text('Delete chat'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Delete chat?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'This chat is linked to worktree "${wt.name}" '
            '(branch ${wt.branch}). What should we do with it?',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AleraTokens.space12),
          Container(
            padding: const EdgeInsets.all(AleraTokens.space12),
            decoration: BoxDecoration(
              color: AleraTokens.surfaceVariant,
              border: Border.all(color: AleraTokens.borderSubtle),
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            ),
            child: Text(
              wt.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(DeleteChatAction.cancel),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(DeleteChatAction.keepWorktree),
          child: const Text('Keep worktree'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(DeleteChatAction.deleteWorktree),
          style: FilledButton.styleFrom(
            backgroundColor: AleraTokens.error,
            foregroundColor: AleraTokens.onError,
          ),
          child: const Text('Delete worktree + branch'),
        ),
      ],
    );
  }
}

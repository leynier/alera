import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

@visibleForTesting
const workspaceBranchRemovalDialogWidthKey = Key(
  'workspace-branch-removal-dialog-width',
);

Future<bool?> showWorkspaceBranchRemovalDialog(
  BuildContext context,
  String? branch,
) => showDialog<bool>(
  context: context,
  builder: (context) => AleraDialog(
    maxWidth: AleraTokens.dialogCompactWidth,
    child: Padding(
      key: workspaceBranchRemovalDialogWidthKey,
      padding: const EdgeInsets.all(AleraTokens.space20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep or Delete Branch?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space12),
          Text(
            branch == null || branch.isEmpty
                ? 'The workspace branch is unknown. Keep its branches when removing the workspace.'
                : 'Keep "$branch" unless you want Alera to attempt safe deletion. Merged branches, including squash and rebase merges, can be deleted. Unmerged or protected branches are retained.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(height: AleraTokens.space20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: branch == null || branch.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Delete Branch'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep Branch'),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);

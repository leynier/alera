import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:flutter/material.dart';

class DeleteWorkspaceDecision {
  const DeleteWorkspaceDecision({required this.deleteBranch});

  final bool deleteBranch;
}

/// Destructive confirmation for removing a managed workspace. [cascadeCount]
/// is the subtree size from `workspaceCascade.preview` (1 = no descendants).
Future<DeleteWorkspaceDecision?> showDeleteWorkspaceDialog(
  BuildContext context, {
  required WorkspaceSummary workspace,
  required int cascadeCount,
}) {
  return showDialog<DeleteWorkspaceDecision>(
    context: context,
    builder: (context) => _DeleteWorkspaceDialog(
      workspace: workspace,
      cascadeCount: cascadeCount,
    ),
  );
}

class _DeleteWorkspaceDialog extends StatelessWidget {
  const _DeleteWorkspaceDialog({
    required this.workspace,
    required this.cascadeCount,
  });

  final WorkspaceSummary workspace;
  final int cascadeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descendants = cascadeCount - 1;
    final deleteBranch = !workspace.reusesExistingBranch;
    return AlertDialog(
      title: const Text('Delete Workspace'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(workspace.name, style: theme.textTheme.titleSmall),
          if (workspace.branch != null) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceXs),
            Text(
              workspace.branch!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: AleraTokens.monoFontFamily,
              ),
            ),
          ],
          if (descendants > 0) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceMd),
            Text(
              'This Workspace Has $descendants Linked '
              '${descendants == 1 ? 'Descendant' : 'Descendants'}. They Will '
              'Be Unlinked, Not Deleted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.warning,
              ),
            ),
          ],
          const SizedBox(height: AleraTokens.spaceMd),
          Text(
            deleteBranch
                ? 'The Alera-Created Branch Will Also Be Deleted.'
                : 'The Existing Branch Will Be Preserved.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(
            context,
          ).pop(DeleteWorkspaceDecision(deleteBranch: deleteBranch)),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

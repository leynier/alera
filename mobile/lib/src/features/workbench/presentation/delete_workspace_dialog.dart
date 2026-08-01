import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
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
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Delete Workspace', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
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
                'This workspace has $descendants linked '
                '${descendants == 1 ? 'descendant' : 'descendants'}. They will '
                'be unlinked, not deleted.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.warning,
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.spaceMd),
            Text(
              deleteBranch
                  ? 'The Alera-created branch will also be deleted.'
                  : 'The existing branch will be preserved.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AleraTokens.error,
                      foregroundColor: AleraTokens.onError,
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(DeleteWorkspaceDecision(deleteBranch: deleteBranch)),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

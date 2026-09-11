import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

@visibleForTesting
const workspaceRemovalDialogWidthKey = Key('workspace-removal-dialog-width');

class const WorkspaceRemovalDecision({required final bool deleteBranch});

Future<WorkspaceRemovalDecision?> showWorkspaceRemovalDialog(
  BuildContext context, {
  required String workspaceName,
  String? branch,
  required bool canDeleteBranch,
  String impactSummary = '',
}) => showDialog<WorkspaceRemovalDecision>(
  context: context,
  builder: (context) => _WorkspaceRemovalDialog(
    workspaceName: workspaceName,
    branch: branch,
    canDeleteBranch: canDeleteBranch,
    impactSummary: impactSummary,
  ),
);

class const _WorkspaceRemovalDialog({
  required final String workspaceName,
  required final bool canDeleteBranch,
  required final String impactSummary,
  final String? branch,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.dialogCompactWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        key: workspaceRemovalDialogWidthKey,
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text('Remove Workspace?', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  _message(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
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
                if (canDeleteBranch)
                  TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const WorkspaceRemovalDecision(deleteBranch: false)),
                    child: const Text('Keep Branch'),
                  ),
                FilledButton(
                  autofocus: true,
                  style: FilledButton.styleFrom(
                    backgroundColor: AleraTokens.error,
                    foregroundColor: AleraTokens.onError,
                  ),
                  onPressed: () => Navigator.of(context).pop(
                    WorkspaceRemovalDecision(deleteBranch: canDeleteBranch),
                  ),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _message() {
    final details = StringBuffer(impactSummary);
    details.write('This removes the worktree for "$workspaceName".');
    final currentBranch = branch;
    if (canDeleteBranch) {
      details.write(
        ' Remove also attempts safe deletion of "$currentBranch". '
        'Merged branches, including squash and rebase merges, can be deleted. '
        'Unmerged or protected branches are retained.',
      );
    } else if (currentBranch == null || currentBranch.isEmpty) {
      details.write(
        ' The workspace branch is unknown. Keep its branches when removing '
        'the workspace.',
      );
    } else {
      details.write(' Branch "$currentBranch" will be kept.');
    }
    details.write(
      '\n\nAll tabs will close and running terminals, agents, and their child '
      'processes will stop. Unsaved changes will be lost. If removal fails, '
      'stopped sessions will not restart automatically.',
    );
    return details.toString();
  }
}

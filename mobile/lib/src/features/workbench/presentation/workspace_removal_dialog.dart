import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_removal_dependency.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:flutter/material.dart';

@visibleForTesting
const workspaceRemovalDialogWidthKey = Key('workspace-removal-dialog-width');

class const WorkspaceRemovalDecision({
  required final bool deleteBranch,
  final bool pauseAutomations = false,
});

typedef DeleteWorkspaceDecision = WorkspaceRemovalDecision;

/// Destructive confirmation for removing a managed workspace. [cascadeCount]
/// is the subtree size from `workspaceCascade.preview` (1 = no descendants).
Future<WorkspaceRemovalDecision?> showWorkspaceRemovalDialog(
  BuildContext context, {
  required WorkspaceSummary workspace,
  int cascadeCount = 1,
  List<WorkspaceRemovalDependency> dependencies = const [],
  String impactSummary = '',
}) {
  return showDialog<WorkspaceRemovalDecision>(
    context: context,
    builder: (context) => _WorkspaceRemovalDialog(
      workspace: workspace,
      cascadeCount: cascadeCount,
      dependencies: dependencies,
      impactSummary: impactSummary,
    ),
  );
}

Future<DeleteWorkspaceDecision?> showDeleteWorkspaceDialog(
  BuildContext context, {
  required WorkspaceSummary workspace,
  required int cascadeCount,
  List<WorkspaceRemovalDependency> dependencies = const [],
  String impactSummary = '',
}) => showWorkspaceRemovalDialog(
  context,
  workspace: workspace,
  cascadeCount: cascadeCount,
  dependencies: dependencies,
  impactSummary: impactSummary,
);

class const _WorkspaceRemovalDialog({
  required final WorkspaceSummary workspace,
  required final int cascadeCount,
  required final List<WorkspaceRemovalDependency> dependencies,
  required final String impactSummary,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descendants = cascadeCount - 1;
    final branch = workspace.branch?.trim();
    final canDeleteBranch =
        !workspace.isMain &&
        !workspace.reusesExistingBranch &&
        branch != null &&
        branch.isNotEmpty;

    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        key: workspaceRemovalDialogWidthKey,
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Remove Workspace?', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _message(canDeleteBranch, branch, descendants),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    if (dependencies.isNotEmpty) ...[
                      const SizedBox(height: AleraTokens.space12),
                      Text(
                        '${dependencies.map((dependency) => '${dependency.name}: ${dependency.activeRuns} active runs').join('\n')}\n\nContinuing pauses these automations when needed and cancels all of their active runs. History is preserved. Their workspace targets must be changed before resuming.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                if (canDeleteBranch)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      WorkspaceRemovalDecision(
                        deleteBranch: false,
                        pauseAutomations: dependencies.isNotEmpty,
                      ),
                    ),
                    child: const Text('Keep Branch'),
                  ),
                FilledButton(
                  autofocus: true,
                  style: FilledButton.styleFrom(
                    backgroundColor: AleraTokens.error,
                    foregroundColor: AleraTokens.onError,
                  ),
                  onPressed: () => Navigator.of(context).pop(
                    WorkspaceRemovalDecision(
                      deleteBranch: canDeleteBranch,
                      pauseAutomations: dependencies.isNotEmpty,
                    ),
                  ),
                  child: Text(
                    dependencies.isEmpty ? 'Remove' : 'Pause And Remove',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _message(
    bool canDeleteBranch,
    String? currentBranch,
    int descendants,
  ) {
    final details = StringBuffer(impactSummary);
    if (workspace.isMain) {
      return 'Remove "${workspace.name}" and close its tabs, terminals and agents? '
          'Files, branches and other workspaces in the project folder will be kept. '
          'If removal fails after processes stop, those processes will not restart automatically.';
    }
    details.write('This removes the worktree for "${workspace.name}".');
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
    if (descendants > 0) {
      details.write(
        '\n\nThis workspace has $descendants linked '
        '${descendants == 1 ? 'descendant' : 'descendants'}. They will '
        'be unlinked, not deleted.',
      );
    }
    details.write(
      '\n\nAll tabs will close and running terminals, agents, and their child '
      'processes will stop. Unsaved changes will be lost. If removal fails, '
      'stopped sessions will not restart automatically.',
    );
    return details.toString();
  }
}

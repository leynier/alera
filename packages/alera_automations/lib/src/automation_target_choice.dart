import 'package:alera_automations/src/automation_draft.dart';
import 'package:alera_automations/src/automation_models.dart';

/// The destinations an editor offers. Both worktree choices write the same
/// `worktree` target and differ only in whether it names a parent workspace.
enum AutomationTargetChoice(
  final AutomationTargetType type,
  final String label, {
  final AutomationWorktreeSource? worktreeSource,
}) {
  freshTab(AutomationTargetType.freshTab, 'New Agent Tab In A Workspace'),
  projectWorktree(
    AutomationTargetType.worktree,
    'New Worktree From A Project',
    worktreeSource: AutomationWorktreeSource.project,
  ),
  workspaceWorktree(
    AutomationTargetType.worktree,
    'New Worktree From A Workspace',
    worktreeSource: AutomationWorktreeSource.workspace,
  ),
  projectCheckout(
    AutomationTargetType.projectCheckout,
    'Project Folder On A Host',
  ),
  existingTab(
    AutomationTargetType.existingTab,
    'Continue An Agent Conversation',
  );

  /// The choice [draft] currently holds, or null before the user picks one.
  static AutomationTargetChoice? of(AutomationDraft draft) =>
      switch (draft.targetType) {
        null => null,
        AutomationTargetType.freshTab => freshTab,
        AutomationTargetType.worktree => switch (draft.worktreeSource) {
          AutomationWorktreeSource.project => projectWorktree,
          AutomationWorktreeSource.workspace => workspaceWorktree,
        },
        AutomationTargetType.projectCheckout => projectCheckout,
        AutomationTargetType.existingTab => existingTab,
      };

  /// Selects this choice in [draft], dropping every field of the previous one.
  AutomationDraft applyTo(AutomationDraft draft) => draft.withTargetType(
    type,
    worktreeSource: worktreeSource ?? AutomationWorktreeSource.project,
  );
}

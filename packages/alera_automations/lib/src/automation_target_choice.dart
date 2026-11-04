import 'package:alera_automations/src/automation_agent_chat_target.dart';
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
  ),

  /// Posts each run into an agent chat, an existing one or a new one per
  /// run. Offered only by a runtime with `automationAgentChatTargetV1`.
  agentChat(AutomationTargetType.agentChat, 'Agent Chat');

  /// The choices a runtime offers; agent chat needs its capability.
  static List<AutomationTargetChoice> offered({required bool agentChat}) =>
      <AutomationTargetChoice>[
        for (final choice in values)
          if (agentChat || choice != AutomationTargetChoice.agentChat) choice,
      ];

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
        AutomationTargetType.agentChat => agentChat,
      };

  /// Selects this choice in [draft], dropping every field of the previous one.
  /// A new agent chat target starts with the most access a chat can have as
  /// its mode ceiling, which the person may lower.
  AutomationDraft applyTo(AutomationDraft draft) {
    if (this == agentChat) {
      if (draft.targetType == AutomationTargetType.agentChat) return draft;
      return draft
          .withTargetType(type)
          .withAgentChat(
            const AutomationAgentChatTarget(
              runtimeModeCeiling: automationDefaultRuntimeModeCeiling,
            ),
          );
    }
    return draft.withTargetType(
      type,
      worktreeSource: worktreeSource ?? AutomationWorktreeSource.project,
    );
  }
}

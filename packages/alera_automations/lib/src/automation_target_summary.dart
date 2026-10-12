import 'package:alera_automations/src/automation_draft.dart';
import 'package:alera_automations/src/automation_models.dart';
import 'package:alera_automations/src/automation_target_choice.dart';

/// Turns the ids a target names into the names the user knows. Each app
/// resolves them from its own workbench state.
abstract interface class AutomationNameLookup {
  String projectName(String? id);

  String workspaceName(String? id);

  String hostName(String? id);

  String profileName(String? id);
}

/// Readable target line, what runs where, never raw ids. A stored definition
/// prefers the runtime's own `targetSummary`, which also covers hosts and
/// projects this client cannot resolve.
String automationTargetSummary(
  AutomationDraft draft,
  AutomationNameLookup names,
) {
  String? value(AutomationDraftField field) => draft.field(field);
  final branch = value(.sourceBranch);
  final where = switch (AutomationTargetChoice.of(draft)) {
    null => 'No target',
    AutomationTargetChoice.freshTab =>
      'New tab in ${names.workspaceName(value(.workspaceId))}',
    AutomationTargetChoice.projectWorktree =>
      'New worktree of ${names.projectName(value(.projectId))} from ${branch ?? 'its default branch'}',
    AutomationTargetChoice.workspaceWorktree =>
      'New worktree from ${names.workspaceName(value(.parentWorkspaceId))}${branch == null ? '' : ' on $branch'}',
    AutomationTargetChoice.projectCheckout =>
      'Folder of ${names.projectName(value(.projectId))} on ${names.hostName(value(.hostId))}',
    AutomationTargetChoice.existingTab =>
      'Conversation in ${names.workspaceName(value(.workspaceId))}',
  };
  final profile = value(.agentProfileId);
  return profile == null || draft.targetType == AutomationTargetType.existingTab
      ? where
      : '$where · ${names.profileName(profile)}';
}

/// [automationTargetSummary] for a stored definition.
String automationRecordTargetSummary(
  AutomationRecord automation,
  AutomationNameLookup names,
) =>
    automation.targetSummary ??
    automationTargetSummary(AutomationDraft.fromRecord(automation), names);

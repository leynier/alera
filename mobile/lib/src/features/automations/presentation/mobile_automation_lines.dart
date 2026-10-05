import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_status_labels.dart';

String mobileAutomationScheduleLine(AutomationRecord automation) {
  if (automation.isCompleted) return 'Completed';
  final description = automationScheduleDescription(automation.schedule);
  final next = automation.nextRunAt;
  if (next == null || automation.state != 'active') return description;
  return '$description · next ${automationRelativeTime(next)}';
}

String mobileAutomationTargetLine(
  AutomationRecord automation,
  MobileAutomationContext names,
) {
  if (automation.targetSummary case final summary?) return summary;
  final details = automation.targetDetails;
  final profile = automation.agentProfileId == null
      ? null
      : names.profileName(automation.agentProfileId);
  final where = switch (automation.targetType) {
    AutomationTargetType.freshTab =>
      'New tab in ${names.workspaceName(automation.targetWorkspaceId)}',
    AutomationTargetType.projectWorktree =>
      'New worktree of ${names.projectName(automationJsonOptionalString(details['projectId']))} from ${automationJsonOptionalString(details['sourceBranch']) ?? 'its default branch'}',
    AutomationTargetType.managedWorkspace =>
      'New worktree from ${names.workspaceName(automation.targetWorkspaceId)}',
    AutomationTargetType.projectCheckout =>
      'Folder of ${names.projectName(automationJsonOptionalString(details['projectId']))} on ${names.hostName(automationJsonOptionalString(details['hostId']))}',
    AutomationTargetType.existingTab =>
      'Conversation in ${names.workspaceName(automation.targetWorkspaceId)}',
    null => 'No target',
  };
  return profile == null ? where : '$where · $profile';
}

String mobileDraftTargetLine(
  AutomationDraft draft,
  MobileAutomationContext names,
) {
  String? value(AutomationDraftField field) => draft.field(field);
  final profile = value(.agentProfileId) == null
      ? ''
      : ' with ${names.profileName(value(.agentProfileId))}';
  return switch (draft.targetType) {
    null => 'No target chosen',
    AutomationTargetType.freshTab =>
      'New agent tab in ${names.workspaceName(value(.workspaceId))}$profile',
    AutomationTargetType.projectWorktree =>
      'New workspace and worktree of ${names.projectName(value(.projectId))} from ${value(.sourceBranch) ?? 'its default branch'}$profile',
    AutomationTargetType.managedWorkspace =>
      'New worktree from ${names.workspaceName(value(.workspaceId))} on ${value(.sourceBranch) ?? 'its branch'}$profile',
    AutomationTargetType.projectCheckout =>
      'Project folder of ${names.projectName(value(.projectId))} on ${names.hostName(value(.hostId))}$profile',
    AutomationTargetType.existingTab =>
      'The agent conversation in ${names.workspaceName(value(.workspaceId))}',
  };
}

String mobileTargetDescription(AutomationTargetType type) => switch (type) {
  AutomationTargetType.freshTab =>
    'Each run opens a new agent tab in a workspace you choose.',
  AutomationTargetType.projectWorktree => 'Each run creates a new workspace with its own worktree and branch from a project branch. Git projects on the paired computer only.',
  AutomationTargetType.managedWorkspace => 'Each run creates a child workspace with its own worktree and branch from a workspace. Git projects on the paired computer only.',
  AutomationTargetType.projectCheckout => 'Each run creates a workspace on a registered project folder. Files are shared.',
  AutomationTargetType.existingTab =>
    'Each run sends the prompt to an agent conversation that is already open.',
};

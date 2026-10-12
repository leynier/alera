import 'package:alera_automations/alera_automations.dart';

String mobileAutomationScheduleLine(AutomationRecord automation) {
  if (automation.isCompleted) return 'Completed';
  final description = automationScheduleDescription(automation.schedule);
  final next = automation.nextRunAt;
  if (next == null || automation.state != 'active') return description;
  return '$description · next ${automationRelativeTime(next)}';
}

String mobileTargetDescription(
  AutomationTargetChoice choice,
) => switch (choice) {
  AutomationTargetChoice.freshTab =>
    'Each run opens a new agent tab in a workspace you choose.',
  AutomationTargetChoice.projectWorktree => 'Each run creates a new workspace with its own worktree and branch from a project branch. Git projects on the paired computer only.',
  AutomationTargetChoice.workspaceWorktree => 'Each run creates a child workspace with its own worktree and branch from a workspace. Git projects on the paired computer only.',
  AutomationTargetChoice.projectCheckout => 'Each run creates a workspace on a registered project folder. Files are shared.',
  AutomationTargetChoice.existingTab =>
    'Each run sends the prompt to an agent conversation that is already open.',
};

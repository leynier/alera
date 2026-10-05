import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';

/// Readable target line: what runs where, never raw ids.
String automationTargetLine(
  AutomationRecord automation,
  AutomationWorkbenchContext names,
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

String automationScheduleLine(AutomationRecord automation) {
  if (automation.isCompleted) return 'Completed';
  final description = automationScheduleDescription(automation.schedule);
  final next = automation.nextRunAt;
  if (next == null || automation.state != 'active') return description;
  return '$description · next ${automationRelativeTime(next)}';
}

class const AutomationListTile({
  required final AutomationRecord automation,
  required final AutomationWorkbenchContext names,
  required final bool selected,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final state = automationStateLabel(automation);
    final lastRun = automation.lastRun;
    final readinessError =
        automation.readiness?.errors.isNotEmpty == true &&
        !automation.isCompleted &&
        !automation.isTrashed;
    return AleraActiveRail(
      active: selected,
      child: ListTile(
        selected: selected,
        selectedTileColor: AleraActiveRail.selectedColor,
        onTap: onTap,
        dense: true,
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(automation.name, maxLines: 1, overflow: .ellipsis),
            ),
            const SizedBox(width: AleraTokens.space6),
            AutomationToneBadge(label: state.label, tone: state.tone),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Text(
              automationScheduleLine(automation),
              maxLines: 1,
              overflow: .ellipsis,
              style: muted,
            ),
            Text(
              automationTargetLine(automation, names),
              maxLines: 1,
              overflow: .ellipsis,
              style: muted,
            ),
            if (automation.attention case final attention?)
              Text(
                attention.message,
                maxLines: 2,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.warning,
                ),
              )
            else if (readinessError)
              Text(
                automation.readiness!.errors.first.message,
                maxLines: 2,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            if (automation.createdByAgent)
              Text(
                'Created by agent ${automation.createdByLabel ?? ''}'.trim(),
                maxLines: 1,
                overflow: .ellipsis,
                style: muted,
              ),
          ],
        ),
        trailing: lastRun == null
            ? null
            : Tooltip(
                message: 'Last run: ${_lastRunLabel(lastRun)}',
                child: AleraStatusDot(
                  active: true,
                  color: automationToneColor(_lastRunTone(lastRun.status)),
                ),
              ),
      ),
    );
  }
}

String _lastRunLabel(AutomationLastRun run) {
  final status = automationRunStatusLabel(
    AutomationRunRecord(
      id: run.id,
      automationId: '',
      number: 0,
      status: run.status,
      trigger: '',
      summary: run.summary,
      error: null,
      scheduledAt: null,
      finishedAt: run.finishedAt,
    ),
  ).label;
  final finished = run.finishedAt;
  return finished == null
      ? status
      : '$status ${automationRelativeTime(finished)}';
}

AutomationTone _lastRunTone(String status) => switch (status) {
  'success' => AutomationTone.success,
  'failure' || 'timeout' => AutomationTone.error,
  'blocked' || 'waitingForUser' => AutomationTone.warning,
  'pending' || 'dispatching' || 'dispatched' => AutomationTone.info,
  _ => AutomationTone.neutral,
};

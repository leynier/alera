import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';

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
              automationRecordTargetSummary(automation, names),
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
                  color: automationToneColor(
                    automationRunStatusTone(lastRun.status),
                  ),
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

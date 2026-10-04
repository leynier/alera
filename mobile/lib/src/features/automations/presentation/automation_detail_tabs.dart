import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_lines.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_row.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_sheet.dart';
import 'package:flutter/material.dart';

class const AutomationDetailOverviewTab({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
  required final MobileAutomationContext names,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readiness = automation.readiness;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Text(
          '${mobileAutomationScheduleLine(automation)}. ${mobileAutomationTargetLine(automation, names)}.',
        ),
        if (automation.attention case final attention?) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          AleraNotice(message: attention.message, icon: AleraIcons.warning),
        ],
        if (readiness != null && !automation.isCompleted)
          for (final issue in readiness.issues) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceSm),
            AleraNotice(
              message: issue.action == null
                  ? issue.message
                  : '${issue.message} ${issue.action}',
              icon: issue.isError ? AleraIcons.warning : AleraIcons.info,
            ),
          ],
        const SizedBox(height: AleraTokens.spaceLg),
        Text('Upcoming', style: theme.textTheme.titleSmall),
        if (automation.state != 'active' || detail.occurrences.isEmpty)
          Text(
            automation.state == 'active'
                ? 'No upcoming scheduled runs.'
                : 'Nothing is scheduled while this automation is ${automationStateLabel(automation).label.toLowerCase()}.',
            style: theme.textTheme.bodySmall,
          )
        else
          for (final occurrence in detail.occurrences.take(5))
            Text(
              '${occurrence['localTime'] ?? occurrence['scheduledAt'] ?? ''}',
            ),
        const SizedBox(height: AleraTokens.spaceLg),
        Text('Prompt', style: theme.textTheme.titleSmall),
        SelectableText(automation.promptTemplate),
      ],
    );
  }
}

class const AutomationDetailRunsTab({
  required final String hostId,
  required final AutomationDetail detail,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final history = automationRunHistory(detail.runs);
    if (history.isEmpty) {
      return const Center(child: Text('No runs yet.'));
    }
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        for (final entry in history)
          switch (entry) {
            AutomationRunHistoryRun(:final run) => MobileAutomationRunRow(
              run: run,
              onTap: () => unawaited(
                showMobileAutomationRun(
                  context,
                  hostId: hostId,
                  automationId: detail.automation.id,
                  runId: run.id,
                ),
              ),
            ),
            AutomationRunHistoryMissed() => MobileMissedRunsRow(missed: entry),
          },
      ],
    );
  }
}

class const AutomationDetailSettingsTab({
  required final AutomationRecord automation,
  required final MobileAutomationContext names,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Schedule', automationScheduleDescription(automation.schedule)),
      ('Target', mobileAutomationTargetLine(automation, names)),
      ('Missed Schedules', automationPolicyLabel(automation.misfirePolicy)),
      ('When Runs Overlap', automationPolicyLabel(automation.overlapPolicy)),
      (
        'Cleanup',
        automationPolicyLabel(automation.cleanupPolicy ?? 'preserve'),
      ),
      (
        'Precheck',
        automationJsonOptionalString(automation.precheck?['command']) ?? 'None',
      ),
      ('Retry Attempts', '${automation.retryMaxAttempts} launches'),
      ('Notify On Success', automation.notifyOnSuccess ? 'On' : 'Off'),
    ];
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        if (!automation.isEditable)
          AleraNotice(
            message: automation.isCompleted
                ? 'Completed automations are read-only. Clone one to schedule it again.'
                : 'Restore this automation to edit it.',
          ),
        for (final (label, value) in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            subtitle: Text(value),
          ),
      ],
    );
  }
}

class const AutomationDetailActivityTab({
  required final List<JsonMap> events,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const Center(child: Text('No activity yet.'));
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        for (final event in events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_activityLabel(automationJsonString(event['action']))),
            subtitle: Text(
              <String>[
                _actorLabel(automationJsonMap(event['actor'])),
                if (automationJsonDate(event['createdAt']) case final date?)
                  automationDateTimeLabel(date),
              ].join(' · '),
            ),
          ),
      ],
    );
  }
}

String _activityLabel(String action) => switch (action) {
  'edit' => 'Edited',
  'create' => 'Created',
  'approve' || 'active' => 'Activated',
  'paused' => 'Paused',
  'blocked' => 'Needs attention',
  'trashed' => 'Moved to Trash',
  'draft' => 'Restored as draft',
  'archived' => 'Completed',
  'takenOver' => 'Run taken over',
  _ => action.isEmpty ? 'Changed' : action,
};

String _actorLabel(JsonMap actor) {
  final label = automationJsonOptionalString(actor['label']);
  final kind = switch (actor['kind']) {
    'humanDesktop' => 'Desktop',
    'authenticatedMobile' => 'Phone',
    'localCli' => 'CLI',
    'managedAgent' => 'Agent',
    _ => 'Runtime',
  };
  return label == null ? kind : '$kind ($label)';
}

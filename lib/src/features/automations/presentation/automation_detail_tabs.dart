import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/automation_list_tile.dart';
import 'package:alera/src/features/automations/presentation/automation_run_panel.dart';
import 'package:alera/src/features/automations/presentation/automation_run_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const AutomationDetailTabs({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
  final String? selectedRunId,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      key: ValueKey<String?>(selectedRunId),
      length: 4,
      initialIndex: selectedRunId == null ? 0 : 1,
      child: Column(
        children: <Widget>[
          const TabBar(
            isScrollable: true,
            tabAlignment: .start,
            tabs: <Widget>[
              Tab(text: 'Overview'),
              Tab(text: 'Runs'),
              Tab(text: 'Settings'),
              Tab(text: 'Activity'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _OverviewTab(automation: automation, detail: detail),
                _RunsTab(
                  automation: automation,
                  detail: detail,
                  selectedRunId: selectedRunId,
                ),
                _SettingsTab(automation: automation),
                _ActivityTab(events: detail.audit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class const _OverviewTab({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final names = ref.watch(automationWorkbenchContextProvider);
    final readiness = automation.readiness;
    final active = detail.runs.where((run) => run.isActive).toList();
    return ListView(
      padding: const EdgeInsets.only(top: AleraTokens.space12),
      children: <Widget>[
        Text(
          '${automationScheduleLine(automation)}. ${automationTargetLine(automation, names)}.',
          style: theme.textTheme.bodyMedium,
        ),
        if (automation.attention case final attention?) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          AleraInlineNotice(tone: .warning, message: attention.message),
        ],
        if (readiness != null && !automation.isCompleted)
          for (final issue in readiness.issues) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            AleraInlineNotice(
              tone: issue.isError ? .error : .warning,
              message: issue.action == null
                  ? issue.message
                  : '${issue.message} ${issue.action}',
            ),
          ],
        if (active.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space16),
          Text('Active Runs', style: theme.textTheme.titleSmall),
          for (final run in active)
            AutomationRunRow(
              run: run,
              selected: false,
              onTap: () => ref
                  .read(automationsNavigationProvider.notifier)
                  .selectRun(automation.id, run.id),
            ),
        ],
        const SizedBox(height: AleraTokens.space16),
        Text('Upcoming', style: theme.textTheme.titleSmall),
        if (automation.state != 'active' || detail.occurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
            child: Text(
              automation.state == 'active'
                  ? 'No upcoming scheduled runs.'
                  : 'Nothing is scheduled while this automation is ${automationStateLabel(automation).label.toLowerCase()}.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          for (final occurrence in detail.occurrences.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${occurrence['localTime'] ?? occurrence['scheduledAt'] ?? ''}',
              ),
            ),
        const SizedBox(height: AleraTokens.space16),
        Text('Prompt', style: theme.textTheme.titleSmall),
        const SizedBox(height: AleraTokens.space8),
        SelectableText(automation.promptTemplate),
      ],
    );
  }
}

class const _RunsTab({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
  final String? selectedRunId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.read(automationsNavigationProvider.notifier);
    final selected = detail.runs
        .where((run) => run.id == selectedRunId)
        .firstOrNull;
    final history = automationRunHistory(detail.runs);
    return ListView(
      padding: const EdgeInsets.only(top: AleraTokens.space12),
      children: <Widget>[
        if (selected != null) ...<Widget>[
          AutomationRunPanel(
            automation: automation,
            run: selected,
            runs: detail.runs,
            attempts: detail.attemptsFor(selected.id),
            onSelectRun: (id) => navigation.selectRun(automation.id, id),
          ),
          const SizedBox(height: AleraTokens.space12),
        ],
        if (history.isEmpty)
          Text('No runs yet.', style: Theme.of(context).textTheme.bodySmall)
        else
          for (final entry in history)
            switch (entry) {
              AutomationRunHistoryRun(:final run) => AutomationRunRow(
                run: run,
                selected: run.id == selectedRunId,
                onTap: () => navigation.selectRun(automation.id, run.id),
              ),
              AutomationRunHistoryMissed() => AutomationMissedRunsRow(
                missed: entry,
              ),
            },
      ],
    );
  }
}

class const _SettingsTab({required final AutomationRecord automation})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(automationWorkbenchContextProvider);
    final schedule = automation.scheduleDetails;
    final rows = <(String, String)>[
      ('Schedule', automationScheduleDescription(automation.schedule)),
      if (automationJsonOptionalString(schedule['startAt']) case final start?)
        ('Starts', start),
      if (automationJsonOptionalString(schedule['endAt']) case final end?)
        ('Ends', end),
      if (automationJsonOptionalString(schedule['maxScheduledRuns'])
          case final max?)
        ('Max Scheduled Runs', max),
      ('Target', automationTargetLine(automation, names)),
      if (automation.associatedWorkspaceId case final workspace?)
        ('Shown In', names.workspaceName(workspace)),
      ('When Runs Overlap', automationPolicyLabel(automation.overlapPolicy)),
      ('Missed Schedules', automationPolicyLabel(automation.misfirePolicy)),
      ('Setup', automationPolicyLabel(automation.setupPolicy)),
      (
        'Cleanup',
        automationPolicyLabel(automation.cleanupPolicy ?? 'preserve'),
      ),
      (
        'Precheck',
        automationJsonOptionalString(automation.precheck?['command']) ?? 'None',
      ),
      ('Retry Attempts', '${automation.retryMaxAttempts} launches'),
      ('Retry Backoff', '${automation.retryBackoffSeconds} seconds'),
      ('Inactivity Timeout', '${automation.inactivityTimeoutSeconds} seconds'),
      ('Heartbeat Interval', '${automation.heartbeatIntervalSeconds} seconds'),
      ('Queue Cap', '${automation.queueCap} runs'),
      ('Notify On Success', automation.notifyOnSuccess ? 'On' : 'Off'),
      if (automation.description.isNotEmpty)
        ('Description', automation.description),
    ];
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(top: AleraTokens.space12),
      children: <Widget>[
        if (!automation.isEditable)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space12),
            child: AleraInlineNotice(
              message: automation.isCompleted
                  ? 'Completed automations are read-only. Clone one to schedule it again.'
                  : 'Restore this automation to edit it.',
            ),
          ),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
            child: Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                SizedBox(
                  width: AleraTokens.automationInfoLabelWidth * 1.6,
                  child: Text(label, style: theme.textTheme.bodySmall),
                ),
                Expanded(child: SelectableText(value)),
              ],
            ),
          ),
      ],
    );
  }
}

class const _ActivityTab({required final List<JsonMap> events})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AleraTokens.space12),
        child: Text(
          'No activity yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: AleraTokens.space12),
      children: <Widget>[
        for (final event in events)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(automationActivityLabel(event)),
            subtitle: Text(
              <String>[
                automationActorLabel(automationJsonMap(event['actor'])),
                if (automationJsonDate(event['createdAt']) case final date?)
                  automationDateTimeLabel(date),
                ?automationJsonOptionalString(
                  automationJsonMap(event['details'])['reason'],
                ),
              ].join(' · '),
            ),
          ),
      ],
    );
  }
}

String automationActivityLabel(JsonMap event) =>
    switch (automationJsonString(event['action'])) {
      'edit' => 'Edited',
      'create' => 'Created',
      'approve' || 'active' => 'Activated',
      'paused' => 'Paused',
      'blocked' => 'Needs attention',
      'trashed' => 'Moved to Trash',
      'draft' => 'Restored as draft',
      'archived' => 'Completed',
      'takenOver' => 'Run taken over',
      final other => other.isEmpty ? 'Changed' : other,
    };

String automationActorLabel(JsonMap actor) {
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

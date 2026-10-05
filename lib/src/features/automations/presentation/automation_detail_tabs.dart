import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/automation_list_tile.dart';
import 'package:alera/src/features/automations/presentation/automation_overview_tab.dart';
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
            dividerColor: AleraTokens.borderSubtle,
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
                Builder(
                  builder: (context) => AutomationOverviewTab(
                    automation: automation,
                    detail: detail,
                    onShowRuns: () =>
                        DefaultTabController.of(context).animateTo(1),
                  ),
                ),
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
    final groups = <(String, String, List<(String, String)>)>[
      (
        'Schedule',
        'When runs start and when the schedule ends.',
        <(String, String)>[
          ('Schedule', automationScheduleDescription(automation.schedule)),
          if (automationJsonOptionalString(schedule['startAt'])
              case final start?)
            ('Starts', start),
          if (automationJsonOptionalString(schedule['endAt']) case final end?)
            ('Ends', end),
          if (automationJsonOptionalString(schedule['maxScheduledRuns'])
              case final max?)
            ('Max Scheduled Runs', max),
          ('Missed Schedules', automationPolicyLabel(automation.misfirePolicy)),
          (
            'When Runs Overlap',
            automationPolicyLabel(automation.overlapPolicy),
          ),
          ('Queue Cap', '${automation.queueCap} runs'),
        ],
      ),
      (
        'Target',
        'Where each run happens and what it leaves behind.',
        <(String, String)>[
          ('Target', automationTargetLine(automation, names)),
          if (automation.associatedWorkspaceId case final workspace?)
            ('Shown In', names.workspaceName(workspace)),
          ('Setup', automationPolicyLabel(automation.setupPolicy)),
          (
            'Cleanup',
            automationPolicyLabel(automation.cleanupPolicy ?? 'preserve'),
          ),
          (
            'Precheck',
            automationJsonOptionalString(automation.precheck?['command']) ??
                'None',
          ),
        ],
      ),
      (
        'Reliability',
        'How Alera retries, watches and gives up on a run.',
        <(String, String)>[
          ('Retry Attempts', '${automation.retryMaxAttempts} launches'),
          ('Retry Backoff', '${automation.retryBackoffSeconds} seconds'),
          (
            'Inactivity Timeout',
            '${automation.inactivityTimeoutSeconds} seconds',
          ),
          (
            'Heartbeat Interval',
            '${automation.heartbeatIntervalSeconds} seconds',
          ),
          (
            'Circuit Breaker',
            'After ${automation.circuitFailureThreshold} failures in a row, waits ${automation.circuitOpenSeconds} seconds',
          ),
          ('Notify On Success', automation.notifyOnSuccess ? 'On' : 'Off'),
        ],
      ),
    ];
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space16),
      children: <Widget>[
        if (!automation.isEditable)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space16),
            child: AleraInlineNotice(
              message: automation.isCompleted
                  ? 'Completed automations are read-only. Clone one to schedule it again.'
                  : 'Restore this automation to edit it.',
            ),
          ),
        for (final (index, (title, description, rows)) in groups.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : AleraTokens.space24),
            child: AleraSettingsGroup(
              title: title,
              description: description,
              children: <Widget>[
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space16,
                      vertical: AleraTokens.space12,
                    ),
                    child: Row(
                      crossAxisAlignment: .start,
                      children: <Widget>[
                        SizedBox(
                          width: AleraTokens.automationInfoLabelWidth * 1.8,
                          child: Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
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
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space16),
      children: <Widget>[
        AleraPanel(
          children: <Widget>[
            for (final event in events)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space16,
                  vertical: AleraTokens.space12,
                ),
                child: Row(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: AleraTokens.space4),
                      child: AleraStatusDot(active: false),
                    ),
                    const SizedBox(width: AleraTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: <Widget>[
                          Text(
                            automationActivityLabel(event),
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (automationJsonOptionalString(
                                automationJsonMap(event['details'])['reason'],
                              )
                              case final reason?)
                            Text(reason, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space12),
                    Text(
                      <String>[
                        automationActorLabel(automationJsonMap(event['actor'])),
                        if (automationJsonDate(event['createdAt'])
                            case final date?)
                          automationDateTimeLabel(date),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
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

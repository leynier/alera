import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_prompt_variables.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/automation_list_tile.dart';
import 'package:alera/src/features/automations/presentation/automation_overview_cards.dart';
import 'package:alera/src/features/automations/presentation/automation_run_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int _recentRunCount = 5;

/// What the automation does, where and when, at a glance: a stat strip over
/// the prompt and recent runs, with the schedule and target beside them.
class const AutomationOverviewTab({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
  required final VoidCallback onShowRuns,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(automationWorkbenchContextProvider);
    final readiness = automation.readiness;
    final notices = <Widget>[
      if (automation.attention case final attention?)
        AleraInlineNotice(tone: .warning, message: attention.message),
      if (readiness != null && !automation.isCompleted)
        for (final issue in readiness.issues)
          AleraInlineNotice(
            tone: issue.isError ? .error : .warning,
            message: issue.action == null
                ? issue.message
                : '${issue.message} ${issue.action}',
          ),
    ];
    final main = <Widget>[
      _PromptCard(prompt: automation.promptTemplate),
      _RecentRunsCard(
        automation: automation,
        detail: detail,
        onShowRuns: onShowRuns,
      ),
    ];
    final side = <Widget>[
      _UpcomingCard(automation: automation, detail: detail),
      _DetailsCard(automation: automation, names: names),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AleraTokens.wideContentBreakpoint;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space16),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              for (final notice in notices) ...<Widget>[
                notice,
                const SizedBox(height: AleraTokens.space8),
              ],
              if (notices.isNotEmpty)
                const SizedBox(height: AleraTokens.space8),
              AutomationStatStrip(automation: automation, detail: detail),
              const SizedBox(height: AleraTokens.space16),
              if (wide)
                Row(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Expanded(flex: 3, child: _CardColumn(children: main)),
                    const SizedBox(width: AleraTokens.space16),
                    Expanded(flex: 2, child: _CardColumn(children: side)),
                  ],
                )
              else
                _CardColumn(children: <Widget>[...main, ...side]),
            ],
          ),
        );
      },
    );
  }
}

class const _CardColumn({required final List<Widget> children})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      for (final (index, child) in children.indexed) ...<Widget>[
        if (index > 0) const SizedBox(height: AleraTokens.space16),
        child,
      ],
    ],
  );
}

class const _PromptCard({required final String prompt})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    return AutomationOverviewCard(
      title: 'Prompt',
      icon: AleraIcons.composer,
      trailing: AleraIconButton(
        tooltip: 'Copy Prompt',
        icon: AleraIcons.copy,
        iconSize: AleraTokens.iconMd,
        onPressed: () =>
            unawaited(Clipboard.setData(ClipboardData(text: prompt))),
      ),
      child: SelectableText.rich(
        TextSpan(
          style: style,
          children: <InlineSpan>[
            for (final segment in automationTemplateSegments(prompt))
              TextSpan(
                text: segment.text,
                style: segment.known == null
                    ? null
                    : AleraTokens.monoCompactStyle.copyWith(
                        color: segment.known!
                            ? AleraTokens.syntaxVariable
                            : AleraTokens.error,
                        backgroundColor: AleraTokens.accentSubtle,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class const _RecentRunsCard({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
  required final VoidCallback onShowRuns,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.read(automationsNavigationProvider.notifier);
    final runs = detail.runs
        .where((run) => run.status != 'misfireSkipped')
        .take(_recentRunCount)
        .toList(growable: false);
    return AutomationOverviewCard(
      title: 'Recent Runs',
      icon: AleraIcons.restore,
      padded: runs.isEmpty,
      trailing: runs.isEmpty
          ? null
          : TextButton(onPressed: onShowRuns, child: const Text('View All')),
      child: runs.isEmpty
          ? Text(
              automation.state == 'active'
                  ? 'No runs yet. Use Run Now to try it before its first scheduled time.'
                  : 'No runs yet.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            )
          : Column(
              children: <Widget>[
                for (final run in runs)
                  AutomationRunRow(
                    run: run,
                    selected: false,
                    onTap: () => navigation.selectRun(automation.id, run.id),
                  ),
              ],
            ),
    );
  }
}

class const _UpcomingCard({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final occurrences = automation.state == 'active'
        ? detail.occurrences.take(5).toList(growable: false)
        : const <JsonMap>[];
    return AutomationOverviewCard(
      title: 'Upcoming',
      icon: AleraIcons.schedule,
      child: occurrences.isEmpty
          ? Text(
              automation.state == 'active'
                  ? 'No upcoming scheduled runs.'
                  : 'Nothing is scheduled while this automation is ${automationStateLabel(automation).label.toLowerCase()}.',
              style: muted,
            )
          : Column(
              children: <Widget>[
                for (final (index, occurrence) in occurrences.indexed)
                  Padding(
                    padding: EdgeInsets.only(
                      top: index == 0 ? 0 : AleraTokens.space8,
                    ),
                    child: _OccurrenceRow(
                      occurrence: occurrence,
                      first: index == 0,
                    ),
                  ),
              ],
            ),
    );
  }
}

class const _OccurrenceRow({
  required final JsonMap occurrence,
  required final bool first,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = DateTime.tryParse(
      automationJsonString(occurrence['localTime']),
    );
    final scheduled = automationJsonDate(occurrence['scheduledAt']);
    final day = local == null ? null : automationOccurrenceDayLabel(local);
    return Row(
      children: <Widget>[
        Container(
          width: AleraTokens.space6,
          height: AleraTokens.space6,
          decoration: BoxDecoration(
            shape: .circle,
            color: first ? AleraTokens.success : AleraTokens.foregroundFaint,
          ),
        ),
        const SizedBox(width: AleraTokens.space12),
        Expanded(
          child: Text(
            day ?? automationJsonString(occurrence['localTime']),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: first
                  ? AleraTokens.foreground
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ),
        if (local != null)
          Text(
            automationClockLabel(local.hour, local.minute),
            style: AleraTokens.monoCompactStyle.copyWith(
              color: first
                  ? AleraTokens.foreground
                  : AleraTokens.foregroundMuted,
            ),
          ),
        if (scheduled != null) ...<Widget>[
          const SizedBox(width: AleraTokens.space12),
          SizedBox(
            width: AleraTokens.space48,
            child: Text(
              automationRelativeTime(scheduled),
              textAlign: .end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class const _DetailsCard({
  required final AutomationRecord automation,
  required final AutomationWorkbenchContext names,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final details = automation.targetDetails;
    final branch = automationJsonOptionalString(details['sourceBranch']);
    final rows = <(IconData, String, String)>[
      (
        AleraIcons.schedule,
        'Schedule',
        automationScheduleDescription(automation.schedule),
      ),
      (
        AleraIcons.folderSpecial,
        'Runs In',
        automation.targetType?.label ?? 'No Target',
      ),
      (
        AleraIcons.workspaceMain,
        'Target',
        automationTargetLine(automation, names),
      ),
      if (branch != null) (AleraIcons.gitBranch, 'Source Branch', branch),
      if (automation.effectiveProjectId case final project?)
        (AleraIcons.folder, 'Project', names.projectName(project)),
      if (automation.agentProfileId case final profile?)
        (AleraIcons.agent, 'Agent Profile', names.profileName(profile)),
      if (automation.associatedWorkspaceId case final workspace?)
        (AleraIcons.section, 'Shown In', names.workspaceName(workspace)),
      if (automation.createdByAgent)
        (
          AleraIcons.account,
          'Created By',
          automation.createdByLabel ?? 'An agent',
        ),
      if (automation.updatedAt case final updated?)
        (AleraIcons.edit, 'Updated', automationRelativeTime(updated)),
    ];
    return AutomationOverviewCard(
      title: 'Details',
      icon: AleraIcons.info,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (automation.description.isNotEmpty) ...<Widget>[
            Text(
              automation.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
          ],
          for (final (index, (icon, label, value)) in rows.indexed)
            Padding(
              padding: EdgeInsets.only(
                top: index == 0 ? 0 : AleraTokens.space8,
              ),
              child: AutomationDetailRow(
                icon: icon,
                label: label,
                value: value,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Mon, Oct 5" for an occurrence's wall-clock time in the automation zone.
String automationOccurrenceDayLabel(DateTime local) {
  final weekday = automationWeekdays
      .firstWhere((entry) => entry.$1 == local.weekday % 7)
      .$2;
  return '$weekday, ${automationDateTimeLabel(local).split(',').first}';
}

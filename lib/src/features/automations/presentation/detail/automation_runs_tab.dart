import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/automations/presentation/automation_run_panel.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AutomationRunFilter(final String label) {
  all('All'),
  running('Running'),
  failed('Failed'),
  skipped('Skipped');

  bool matches(AutomationRunRecord run) => switch (this) {
    all => true,
    running => run.isActive,
    failed => const <String>{
      'failure',
      'timeout',
      'blocked',
    }.contains(run.status),
    skipped => run.status.endsWith('Skipped'),
  };
}

/// Run history with a status filter. The selected run opens its panel above
/// the list; consecutive missed runs collapse into one row.
class AutomationRunsTab extends ConsumerStatefulWidget {
  const AutomationRunsTab({
    super.key,
    required this.automation,
    required this.detail,
    this.selectedRunId,
  });

  final AutomationRecord automation;
  final AutomationDetail detail;
  final String? selectedRunId;

  @override
  ConsumerState<AutomationRunsTab> createState() => _AutomationRunsTabState();
}

class _AutomationRunsTabState extends ConsumerState<AutomationRunsTab> {
  AutomationRunFilter _filter = AutomationRunFilter.all;

  @override
  Widget build(BuildContext context) {
    final navigation = ref.read(activityNavigationProvider.notifier);
    final automation = widget.automation;
    final runs = widget.detail.runs;
    final selected = runs
        .where((run) => run.id == widget.selectedRunId)
        .firstOrNull;
    final history = automationRunHistory(
      runs.where(_filter.matches).toList(growable: false),
    );
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (selected != null) ...<Widget>[
          AutomationRunPanel(
            automation: automation,
            run: selected,
            runs: runs,
            attempts: widget.detail.attemptsFor(selected.id),
            onSelectRun: (id) =>
                navigation.selectAutomationRun(automation.id, id),
          ),
          const SizedBox(height: AleraTokens.space12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: AleraSegmentedButton<AutomationRunFilter>(
            dense: true,
            selected: _filter,
            segments: <ButtonSegment<AutomationRunFilter>>[
              for (final filter in AutomationRunFilter.values)
                ButtonSegment(value: filter, label: Text(filter.label)),
            ],
            onSelectionChanged: (filter) => setState(() => _filter = filter),
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        if (history.isEmpty)
          Text(
            runs.isEmpty
                ? automation.state == 'active'
                      ? 'No runs yet. Use Run Now to try it before its first scheduled time.'
                      : 'No runs yet.'
                : 'No runs match this filter.',
            style: muted,
          )
        else
          for (final entry in history)
            switch (entry) {
              AutomationRunHistoryRun(:final run) => _RunRow(
                run: run,
                selected: run.id == widget.selectedRunId,
                onPressed: () =>
                    navigation.selectAutomationRun(automation.id, run.id),
              ),
              final AutomationRunHistoryMissed missed => AleraActivityRow(
                title: 'Missed While Runtime Was Off',
                subtitle:
                    '${missed.runs.length} scheduled runs missed their start window and were skipped.',
                metadata: missed.from == null || missed.to == null
                    ? null
                    : '${automationDateTimeLabel(missed.from!)} to ${automationDateTimeLabel(missed.to!)}',
                onPressed: () => navigation.selectAutomationRun(
                  automation.id,
                  missed.runs.first.id,
                ),
              ),
            },
      ],
    );
  }
}

class const _RunRow({
  required final AutomationRunRecord run,
  required final bool selected,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = automationRunStatusLabel(run);
    final started = run.startedAt ?? run.scheduledAt;
    return AleraActivityRow(
      title:
          '#${run.number} · ${run.summary ?? run.error ?? '${_trigger(run)} run'}',
      subtitle: status.label,
      metadata: <String>[
        _trigger(run),
        if (started != null) automationDateTimeLabel(started),
        if (run.finishedAt != null && started != null)
          automationShortDuration(run.finishedAt!.difference(started)),
        if (run.reuse case final reuse?) reuse.label,
      ].join(' · '),
      selected: selected,
      statusColor: automationToneColor(status.tone),
      onPressed: onPressed,
    );
  }

  static String _trigger(AutomationRunRecord run) =>
      run.trigger == 'manual' ? 'Manual' : 'Scheduled';
}

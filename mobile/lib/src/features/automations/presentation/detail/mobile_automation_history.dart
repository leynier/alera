import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_row.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_sheet.dart';
import 'package:flutter/material.dart';

enum _HistoryTab(final String label) {
  runs('Runs'),
  activity('Activity'),
}

enum MobileAutomationRunFilter(final String label) {
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

/// Runs (filtered by status) or the audit trail of one automation. A run
/// opens its sheet; consecutive missed runs collapse into one row.
class MobileAutomationHistory extends StatefulWidget {
  const MobileAutomationHistory({
    super.key,
    required this.hostId,
    required this.detail,
  });

  final String hostId;
  final AutomationDetail detail;

  @override
  State<MobileAutomationHistory> createState() =>
      _MobileAutomationHistoryState();
}

class _MobileAutomationHistoryState extends State<MobileAutomationHistory> {
  _HistoryTab _tab = _HistoryTab.runs;
  MobileAutomationRunFilter _filter = MobileAutomationRunFilter.all;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        SegmentedButton<_HistoryTab>(
          showSelectedIcon: false,
          segments: <ButtonSegment<_HistoryTab>>[
            for (final tab in _HistoryTab.values)
              ButtonSegment(value: tab, label: Text(tab.label)),
          ],
          selected: <_HistoryTab>{_tab},
          onSelectionChanged: (selection) =>
              setState(() => _tab = selection.single),
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        ...switch (_tab) {
          _HistoryTab.runs => _runs(context, muted),
          _HistoryTab.activity => _activity(muted),
        },
      ],
    );
  }

  List<Widget> _runs(BuildContext context, TextStyle? muted) {
    final detail = widget.detail;
    final runs = detail.runs;
    final history = automationRunHistory(
      runs.where(_filter.matches).toList(growable: false),
    );
    return <Widget>[
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final (index, filter)
                in MobileAutomationRunFilter.values.indexed)
              Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : AleraTokens.spaceXs,
                ),
                child: ChoiceChip(
                  label: Text(filter.label),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
              ),
          ],
        ),
      ),
      if (history.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.spaceMd),
          child: Text(
            runs.isEmpty
                ? detail.automation.state == 'active'
                      ? 'No runs yet. Use Run Now to try it before its first scheduled time.'
                      : 'No runs yet.'
                : 'No runs match this filter.',
            style: muted,
          ),
        )
      else
        for (final entry in history)
          switch (entry) {
            AutomationRunHistoryRun(:final run) => MobileAutomationRunRow(
              run: run,
              onTap: () => unawaited(
                showMobileAutomationRun(
                  context,
                  hostId: widget.hostId,
                  automationId: detail.automation.id,
                  runId: run.id,
                ),
              ),
            ),
            AutomationRunHistoryMissed() => MobileMissedRunsRow(missed: entry),
          },
    ];
  }

  List<Widget> _activity(TextStyle? muted) {
    final events = widget.detail.audit;
    if (events.isEmpty) {
      return <Widget>[Text('No activity yet.', style: muted)];
    }
    return <Widget>[
      for (final event in events)
        ListTile(
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
    ];
  }
}

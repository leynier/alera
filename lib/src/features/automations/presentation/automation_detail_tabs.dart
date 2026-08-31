import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/automation_detail_widgets.dart';
import 'package:alera/src/features/automations/presentation/automation_run_row.dart';
import 'package:flutter/material.dart';

class const AutomationOverviewTab({
  required final AutomationDetail detail,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final active = detail.runs.where(
      (run) => !_finalStatuses.contains(run.status),
    );
    final next = detail.occurrences.take(5);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AutomationInfoPanel(automation: detail.automation),
          const SizedBox(height: AleraTokens.space12),
          Text('Prompt Preview', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AleraTokens.space8),
          SelectableText(detail.automation.promptTemplate),
          const SizedBox(height: AleraTokens.space12),
          Text(
            'Effective Policy',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraPanel(
            children: <Widget>[
              for (final entry in detail.effectivePolicies.entries)
                AutomationInfoRow(label: entry.key, value: '${entry.value}'),
            ],
          ),
          const SizedBox(height: AleraTokens.space12),
          Text(
            'Signature Timeline',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AleraTokens.space8),
          if (active.isEmpty && next.isEmpty)
            const Text('No active run or upcoming occurrence.')
          else ...<Widget>[
            for (final run in active)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  AleraIcons.loading,
                  color: AleraTokens.info,
                ),
                title: Text('Active Run #${run.number}'),
                subtitle: Text(run.status),
              ),
            for (final occurrence in next)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AleraIcons.checks),
                title: Text(
                  '${occurrence['localTime'] ?? occurrence['scheduledAt'] ?? 'Upcoming'}',
                ),
                subtitle: const Text('Scheduled occurrence'),
              ),
          ],
        ],
      ),
    );
  }
}

class const AutomationRunsTab({
  required final List<AutomationRunRecord> runs,
  final ValueChanged<AutomationRunRecord>? onCancel,
  final ValueChanged<AutomationRunRecord>? onResumeWaiting,
  final ValueChanged<AutomationRunRecord>? onExtendWaiting,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: AleraTokens.space12),
      children: runs.isEmpty
          ? const <Widget>[Text('No runs yet.')]
          : <Widget>[
              for (final run in runs)
                AutomationRunRow(
                  run: run,
                  onCancel: _isFinal(run.status) || onCancel == null
                      ? null
                      : () => onCancel!(run),
                  onResumeWaiting:
                      run.status != 'waitingForUser' || onResumeWaiting == null
                      ? null
                      : () => onResumeWaiting!(run),
                  onExtendWaiting:
                      run.status != 'waitingForUser' || onExtendWaiting == null
                      ? null
                      : () => onExtendWaiting!(run),
                ),
            ],
    );
  }
}

class const AutomationAuditTab({required final List<JsonMap> events, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: AleraTokens.space12),
      children: events.isEmpty
          ? const <Widget>[Text('No audit events yet.')]
          : <Widget>[
              for (final event in events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(event['action']?.toString() ?? 'Event'),
                  subtitle: Text(
                    '${event['createdAt'] ?? ''} · ${event['actor'] ?? ''}',
                  ),
                ),
            ],
    );
  }
}

const _finalStatuses = <String>{
  'success',
  'failure',
  'blocked',
  'timeout',
  'cancelled',
  'precheckSkipped',
  'misfireSkipped',
  'overlapSkipped',
  'queueLimitSkipped',
};

bool _isFinal(String status) => _finalStatuses.contains(status);

import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_actions.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_detail_actions.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_gate_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gates first, then the objective, the plan, the coordinator and the run's
/// main actions.
class const RunOverviewTab({
  super.key,
  required final String hostId,
  required final RunDetail detail,
  final String? initialGateId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final run = detail.run;
    final gates = <RunGate>[
      ...detail.pendingGates.where((gate) => gate.id == initialGateId),
      ...detail.pendingGates.where((gate) => gate.id != initialGateId),
    ];
    final initialGatePending = gates.any((gate) => gate.id == initialGateId);
    final actions = availableRunActions(detail);
    final busy = ref.watch(mobileRunActionsProvider(hostId, run.id)).anyBusy;
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(mobileRunDetailProvider(hostId, run.id).future),
      child: ListView(
        padding: AleraTokens.pagePadding,
        children: <Widget>[
          if (initialGateId case final gateId? when !initialGatePending)
            _DecidedGate(hostId: hostId, runId: run.id, gateId: gateId),
          for (final gate in gates)
            RunGateSection(
              key: ValueKey<String>('gate-section-${gate.id}'),
              hostId: hostId,
              runId: run.id,
              gate: gate,
              highlighted: gate.id == initialGateId,
            ),
          if (_attentionLine(detail) case final line?)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space8),
              child: AleraNotice(icon: AleraIcons.warning, message: line),
            ),
          const AleraSectionHeader(label: 'Objective'),
          SelectableText(detail.objective, style: theme.textTheme.bodyMedium),
          if (detail.objectiveTruncated)
            Text('The objective is longer than this preview.', style: muted),
          const AleraSectionHeader(label: 'Run'),
          _Fact(label: 'Template', value: _templateLabel(detail)),
          _Fact(label: 'Isolation', value: run.isolation.label),
          if (detail.plan case final plan?)
            _Fact(
              label: 'Plan',
              value:
                  'Rev ${plan.revision} · ${_planStateLabel(plan.state)}${plan.changeReason == null ? '' : ' · ${plan.changeReason}'}',
            ),
          _Fact(
            label: 'Coordinator',
            value: _coordinatorLabel(detail.coordinator.state),
          ),
          if (detail.integrationBranch case final branch?)
            _Fact(
              label: 'Integration',
              value: '$branch ${shortSha(detail.integrationSha)}'.trim(),
            ),
          if (detail.maxConcurrent > 0)
            _Fact(
              label: 'Concurrent Workers',
              value: '${detail.maxConcurrent}',
            ),
          if (detail.stopReason case final reason?)
            _Fact(label: 'Stopped', value: reason),
          if (detail.cleanup case final cleanup?)
            _Fact(
              label: 'Cleanup',
              value: cleanup.abandoned
                  ? 'Abandoned'
                  : '${cleanup.state[0].toUpperCase()}${cleanup.state.substring(1)}',
            ),
          if (run.isolation == RunIsolation.isolated && !run.isFinished)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space8),
              child: Text(
                'Retained worktrees and branches stay until you clean up. Selecting removes nothing until you confirm a preview.',
                style: muted,
              ),
            ),
          const SizedBox(height: AleraTokens.space16),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              for (final action in actions)
                if (action != RunMenuAction.requestChanges &&
                    action != RunMenuAction.cancel)
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            performRunAction(
                              context,
                              ref,
                              hostId: hostId,
                              detail: detail,
                              action: action,
                            ),
                          ),
                    child: Text(action.label),
                  ),
              if (actions.contains(RunMenuAction.cancel))
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AleraTokens.error,
                  ),
                  onPressed: busy
                      ? null
                      : () => unawaited(
                          performRunAction(
                            context,
                            ref,
                            hostId: hostId,
                            detail: detail,
                            action: RunMenuAction.cancel,
                          ),
                        ),
                  child: const Text('Cancel Run'),
                ),
            ],
          ),
          const SizedBox(height: AleraTokens.spaceXxl),
        ],
      ),
    );
  }
}

/// A gate a notification pointed at that someone already decided.
class const _DecidedGate({
  required final String hostId,
  required final String runId,
  required final String gateId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(mobileRunGateProvider(hostId, gateId)).value?.gate;
    if (gate == null) return const SizedBox.shrink();
    return RunGateSection(
      hostId: hostId,
      runId: runId,
      gate: gate,
      highlighted: true,
    );
  }
}

String? _attentionLine(RunDetail detail) {
  final run = detail.run;
  if (detail.coordinator.error case final error?) return error;
  if (run.attentionReason case final reason?) return reason;
  if (run.status == 'paused' && run.pausedBy == 'user') {
    return 'Paused. Workers wait until you resume the run.';
  }
  return null;
}

String _templateLabel(RunDetail detail) {
  final id = detail.recipeId;
  if (id == null) {
    return detail.run.isolation == RunIsolation.shared ? 'None' : 'Freeform';
  }
  return id
      .split(RegExp('[-_]'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _planStateLabel(String state) => switch (state) {
  'awaitingApproval' => 'Awaiting Approval',
  'approved' => 'Approved',
  'planning' => 'Changes Requested',
  'superseded' => 'Superseded',
  _ => state,
};

String _coordinatorLabel(String state) => switch (state) {
  'reserved' => 'Starting',
  'started' => 'Running',
  'attention' => 'Needs Attention',
  'none' => 'None',
  _ => state,
};

class const _Fact({required final String label, required final String value})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          SizedBox(
            width: AleraTokens.keyColumnWidth,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

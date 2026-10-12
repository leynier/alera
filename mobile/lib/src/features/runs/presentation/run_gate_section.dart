import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_actions.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_inspection_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_gate_card.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A gate card wired to the run: loads its evidence, sends the decision with
/// the evidence digest it was shown, and turns stale when the runtime says
/// the evidence moved.
class const RunGateSection({
  super.key,
  required final String hostId,
  required final String runId,
  required final RunGate gate,
  final bool highlighted = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionsProvider = mobileRunActionsProvider(hostId, runId);
    final actions = ref.watch(actionsProvider);
    final detail = ref.watch(mobileRunGateProvider(hostId, gate.id)).value;
    // The freshest copy of the gate, so a decision carries its current digest.
    final current = detail?.gate.id == gate.id ? detail!.gate : gate;
    return RunGateCard(
      gate: current,
      evidence: detail == null ? null : _evidenceLine(detail),
      busy: actions.isBusy(runGateActionKey(gate.id)),
      stale: actions.staleGateIds.contains(gate.id),
      highlighted: highlighted,
      onRefresh: () => ref.read(actionsProvider.notifier).clearStale(gate.id),
      onViewEvidence: detail == null || !_hasEvidence(detail)
          ? null
          : () => unawaited(showRunGateEvidence(context, detail)),
      onDecide: (decision, reason) =>
          unawaited(_decide(context, ref, current, decision, reason)),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    RunGate gate,
    String decision,
    String? reason,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resolution = await ref
          .read(mobileRunActionsProvider(hostId, runId).notifier)
          .resolveGate(gate, decision, reason: reason);
      if (resolution == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (decision) {
            'approve' => 'Approved.',
            'reject' => 'Rejected. The run is cancelled.',
            'requestChanges' => 'Changes requested. The coordinator replans.',
            _ => 'Decision sent.',
          }),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(runErrorMessage(error))));
    }
  }
}

bool _hasEvidence(RunGateDetail detail) =>
    detail.tasks.isNotEmpty || (detail.plan?.tasks.isNotEmpty ?? false);

String? _evidenceLine(RunGateDetail detail) {
  if (detail.plan case final plan? when detail.gate.kind == RunGateKind.plan) {
    final stages = plan.stages.length;
    return '${plan.tasks.length} tasks in $stages ${stages == 1 ? 'stage' : 'stages'} · Rev ${plan.revision}';
  }
  if (detail.tasks.isEmpty) return null;
  final integrated = detail.tasks
      .where((task) => task.integrationState == 'integrated')
      .length;
  final done = detail.tasks.where((task) => task.status == 'completed').length;
  return detail.gate.kind == RunGateKind.stage
      ? '$integrated/${detail.tasks.length} tasks integrated.'
      : '$done/${detail.tasks.length} tasks completed.';
}

/// The tasks (or the proposed plan) a gate is judged on.
Future<void> showRunGateEvidence(BuildContext context, RunGateDetail detail) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (context) => SafeArea(
        child: ListView(
          padding: AleraTokens.pagePadding,
          shrinkWrap: true,
          children: <Widget>[
            if (detail.plan case final plan?) ...<Widget>[
              AleraSectionHeader(label: 'Plan · Rev ${plan.revision}'),
              if (plan.changeReason case final reason?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space8),
                  child: Text('Changes requested: $reason'),
                ),
              for (final stage in plan.stages) ...<Widget>[
                AleraSectionHeader(label: stage.title),
                for (final task in plan.tasks.where(
                  (task) => task.stageId == stage.id,
                ))
                  _EvidenceRow(title: task.title, body: task.spec),
              ],
              for (final task in plan.tasks.where(
                (task) =>
                    task.stageId == null ||
                    !plan.stages.any((stage) => stage.id == task.stageId),
              ))
                _EvidenceRow(title: task.title, body: task.spec),
            ],
            if (detail.tasks.isNotEmpty) ...<Widget>[
              const AleraSectionHeader(label: 'Evidence'),
              const Padding(
                padding: EdgeInsets.only(bottom: AleraTokens.space8),
                child: Text(
                  'Worker-reported evidence is not an independent review.',
                ),
              ),
              for (final task in detail.tasks)
                _EvidenceRow(
                  title: task.title,
                  status: runTaskStatusLabel(
                    task.status,
                    attemptState: task.integrationState,
                  ),
                  body: <String>[
                    ?task.resultPreview,
                    if (task.integrationSha case final sha?)
                      'Integrated at ${shortSha(sha)}',
                    if (task.conflictPaths.isNotEmpty)
                      'Conflicts: ${task.conflictPaths.join(', ')}',
                  ].join('\n'),
                ),
            ],
          ],
        ),
      ),
    );

class const _EvidenceRow({
  required final String title,
  final String body = '',
  final RunStatusLabel? status,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                if (status case final status?)
                  AleraBadge(label: status.label, tone: status.tone),
              ],
            ),
            if (body.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.space4),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

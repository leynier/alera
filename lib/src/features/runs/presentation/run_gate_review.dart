import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';

/// Review Plan, expanded inside a plan gate card: every stage with its
/// tasks, specs and frozen inputs.
class const RunPlanReview({super.key, required final RunPlanView plan})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final reason = plan.changeReason?.trim();
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text(
          '${plan.tasks.length} ${plan.tasks.length == 1 ? 'task' : 'tasks'} in ${plan.stages.length} ${plan.stages.length == 1 ? 'stage' : 'stages'}'
          '${plan.sourceSha == null ? '' : ' from ${shortSha(plan.sourceSha)}'}'
          '${plan.recipeName == null ? '' : ' · ${plan.recipeName}'}'
          ' · up to ${plan.maxConcurrent} concurrent ${plan.maxConcurrent == 1 ? 'worker' : 'workers'}.',
          style: muted,
        ),
        if (reason != null && reason.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Text('Requested changes: $reason', style: muted),
        ],
        for (final stage in plan.stages) ...<Widget>[
          AleraSectionHeader(
            label:
                '${stage.label}${stage.gate ? ' · ${stageGateKindLabel(stage.gateKind) ?? 'Stage'} gate' : ''}',
            padding: const EdgeInsets.only(
              top: AleraTokens.space12,
              bottom: AleraTokens.space4,
            ),
          ),
          if (stage.profile != null)
            Text('Profile: ${stage.profile}', style: muted),
          for (final task in plan.tasks.where((t) => t.stageId == stage.id))
            _PlanTask(task: task),
        ],
        if (plan.stages.isEmpty)
          for (final task in plan.tasks) _PlanTask(task: task),
      ],
    );
  }
}

class const _PlanTask({required final RunPlanTask task})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final inputs = task.inputs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space4,
        children: <Widget>[
          Text(task.title, style: theme.textTheme.bodyMedium),
          Text(
            <String>[
              task.id,
              if (task.roleId != null) 'Role ${task.roleId}',
              if (task.dependsOn.isNotEmpty)
                'Depends On ${task.dependsOn.join(', ')}',
              if (task.correctsTaskId != null)
                'Corrects ${task.correctsTaskId}',
            ].join(' · '),
            style: AleraTokens.monoCompactStyle,
          ),
          if (task.spec.isNotEmpty) SelectableText(task.spec, style: muted),
          if (inputs != null)
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(inputs),
              style: AleraTokens.monoCompactStyle,
            ),
        ],
      ),
    );
  }
}

/// View Evidence, expanded inside a stage gate card: the results and
/// integrations the approval binds.
class const RunGateEvidence({super.key, required final RunGateDetail detail})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final gate = detail.gate;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space8,
      children: <Widget>[
        if (gate.kind == RunGateKind.stage)
          Text(
            'Approval binds this revision, integration ${shortSha(gate.integrationSha)} and the artifact evidence below. Changed evidence needs another review.',
            style: muted,
          ),
        Text(
          'Worker-reported evidence is not an independent review.',
          style: muted,
        ),
        if (detail.tasks.isEmpty)
          Text('No task evidence is recorded for this gate.', style: muted),
        for (final task in detail.tasks)
          Column(
            crossAxisAlignment: .stretch,
            spacing: AleraTokens.space4,
            children: <Widget>[
              Row(
                spacing: AleraTokens.space8,
                children: <Widget>[
                  Expanded(
                    child: Text(task.title, style: theme.textTheme.bodyMedium),
                  ),
                  AleraBadge(
                    label: taskStatusLabel(task.integrationState ?? task.status)
                        .label,
                    tone: taskStatusLabel(task.integrationState ?? task.status)
                        .tone,
                  ),
                ],
              ),
              Text(
                <String>[
                  task.logicalId ?? task.taskId,
                  if (task.integrationSha != null)
                    'Integrated ${shortSha(task.integrationSha)}',
                  if (task.assignee != null) task.assignee!,
                ].join(' · '),
                style: AleraTokens.monoCompactStyle,
              ),
              if (task.resultPreview != null)
                SelectableText(
                  '${task.resultPreview}${task.resultTruncated ? '…' : ''}',
                  style: muted,
                ),
              if (task.conflictPaths.isNotEmpty)
                SelectableText(
                  task.conflictPaths.join('\n'),
                  style: AleraTokens.monoCompactStyle,
                ),
            ],
          ),
      ],
    );
  }
}

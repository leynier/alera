import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cancellation_control.dart';
import 'package:flutter/material.dart';

class WorkflowRunControlPanel extends StatelessWidget {
  const WorkflowRunControlPanel({
    super.key,
    required this.controls,
    required this.onControl,
    required this.onReview,
    required this.onRefresh,
    this.busy = false,
    this.error,
    this.onRetry,
  });
  final WorkflowRunControls controls;
  final ValueChanged<String> onControl;
  final ValueChanged<String> onReview;
  final VoidCallback onRefresh;
  final bool busy;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final execution = controls.execution;
    final running = controls.canControl && execution?.status == 'running';
    final enabled = !busy && onRetry == null && error == null;
    final names = {for (final stage in controls.stages) stage.id: stage.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${controls.recipeName} (${controls.recipeOrigin})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AleraTokens.space8),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            AleraBadge(label: 'Revision ${controls.revision}'),
            AleraBadge(
              label: controls.status == 'completed'
                  ? 'Completed'
                  : controls.status == 'cancelled'
                  ? controls.cancellationError != null
                        ? 'Attention'
                        : controls.cancellationPending > 0
                        ? 'Cancelling'
                        : 'Cancelled'
                  : running
                  ? 'Running'
                  : 'Not Running',
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space12),
        Text(
          controls.status == 'completed'
              ? 'All results are integrated and required human gates are approved. Worktrees and branches are retained.'
              : controls.status == 'cancelled'
              ? controls.cancellationPending > 0
                    ? 'New tasks are blocked. ${controls.cancellationPending} agent terminals await settlement.'
                    : 'The run is cancelled and its agent terminals are stopped. Worktrees, branches and results are retained.'
              : running
              ? 'The runtime continues while this Board is closed. Pause stops new workers; active workers keep their work.'
              : controls.canControl
              ? 'Start executes the approved plan in isolated worktrees. Every required stage gate remains a human decision.'
              : 'Execution is unavailable until the current plan is approved and the run is active.',
        ),
        if (execution?.attention case final String reason) ...[
          const SizedBox(height: AleraTokens.space12),
          Text(
            'Attention',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: AleraTokens.warning),
          ),
          SelectableText(reason),
        ],
        if (error != null) ...[
          const SizedBox(height: AleraTokens.space12),
          SelectableText(error.toString()),
        ],
        const SizedBox(height: AleraTokens.space12),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            if (controls.canControl)
              FilledButton(
                onPressed: enabled
                    ? () => onControl(running ? 'pause' : 'start')
                    : null,
                child: Text(running ? 'Pause Workflow' : 'Start Workflow'),
              ),
            if (onRetry != null)
              OutlinedButton(
                onPressed: busy ? null : onRetry,
                child: const Text('Retry Same Command'),
              ),
            OutlinedButton(
              onPressed: busy ? null : onRefresh,
              child: const Text('Refresh Workflow'),
            ),
          ],
        ),
        if (onRetry != null)
          const Padding(
            padding: EdgeInsets.only(top: AleraTokens.space8),
            child: Text(
              'The command outcome is uncertain. Retry keeps the same identity and cannot start duplicate workers.',
            ),
          ),
        WorkflowCancellationControl(
          key: ValueKey('cancel:${controls.runId}:${controls.revision}'),
          controls: controls,
          enabled: enabled,
          onCancel: () => onControl('cancel'),
        ),
        const SizedBox(height: AleraTokens.space16),
        ExpansionTile(
          key: PageStorageKey('workflow-commits:${controls.runId}'),
          title: const Text('Source And Integration'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Source Commit'),
                  SelectableText(
                    controls.sourceSha,
                    style: AleraTokens.monoCompactStyle,
                    key: PageStorageKey('workflow-source:${controls.runId}'),
                  ),
                  const SizedBox(height: AleraTokens.space8),
                  const Text('Integration Commit'),
                  SelectableText(
                    controls.integrationSha,
                    style: AleraTokens.monoCompactStyle,
                    key: PageStorageKey(
                      'workflow-integration:${controls.runId}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        for (final stage in controls.stages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stage.name, style: Theme.of(context).textTheme.titleSmall),
                Text('${stage.integratedCount}/${stage.taskCount} integrated'),
                if (stage.dependsOn.isNotEmpty)
                  Text(
                    'After: ${stage.dependsOn.map((id) => names[id] ?? id).join(', ')}',
                  ),
                if (stage.gate != null) ...[
                  Text(
                    stage.gateStatus == 'approved'
                        ? 'Human gate approved.'
                        : stage.canReview
                        ? 'Integrated evidence is ready for your review.'
                        : 'Human gate waits for integrated evidence and prerequisite approvals.',
                  ),
                  OutlinedButton(
                    onPressed: enabled && stage.canReview
                        ? () => onReview('stage:${stage.id}')
                        : null,
                    child: Text(
                      stage.gate == 'foundation'
                          ? 'Review Foundation Gate'
                          : 'Review Product Gate',
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

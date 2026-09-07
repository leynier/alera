import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/orchestration/domain/workflow_review_snapshot.dart';
import 'package:flutter/material.dart';

class WorkflowReviewPanel extends StatefulWidget {
  const WorkflowReviewPanel({
    super.key,
    required this.review,
    required this.onDecision,
    required this.onBack,
    required this.onRefresh,
    required this.onInspectTask,
    this.busy = false,
    this.invalidated = false,
    this.error,
  });

  final WorkflowReviewSnapshot review;
  final void Function(WorkflowHumanDecision, String) onDecision;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onInspectTask;
  final bool busy;
  final bool invalidated;
  final String? error;

  @override
  State<WorkflowReviewPanel> createState() => _WorkflowReviewPanelState();
}

class _WorkflowReviewPanelState extends State<WorkflowReviewPanel> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WorkflowReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.review.runId != widget.review.runId) _reason.clear();
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final plan = review.plan;
    final recipe = (plan['recipe']! as Map)['recipe']! as Map;
    final stages = recipe['stages']! as List;
    final tasks = plan['tasks']! as List;
    final planReview = review.scope == 'plan';
    final correctionReview = review.scope == 'correction';
    final enabled = !widget.busy && !widget.invalidated;
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.busy ? null : widget.onBack,
            child: const Text('Back To Run'),
          ),
        ),
        Text(
          planReview
              ? 'Review Plan'
              : correctionReview
              ? 'Review Changes Needed'
              : 'Review Stage Gate',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AleraTokens.space12),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            AleraBadge(label: 'Revision ${review.revision}'),
            const AleraBadge(label: 'Human Approval'),
          ],
        ),
        const SizedBox(height: AleraTokens.space12),
        SelectableText(plan['objective']! as String),
        const SizedBox(height: AleraTokens.space12),
        Text('Recipe', style: Theme.of(context).textTheme.labelMedium),
        Text(
          '${recipe['name']} (${_originLabel((plan['recipe']! as Map)['source']! as Map)})',
        ),
        const SizedBox(height: AleraTokens.space8),
        Text(
          'Integration Commit',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        SelectableText(
          review.challenge['integrationSha']! as String,
          style: AleraTokens.monoCompactStyle,
        ),
        const SizedBox(height: AleraTokens.space8),
        Text(
          correctionReview
              ? 'Requesting changes creates a new revision for a corrective plan. Completed work and retained worktrees are preserved. This action does not approve or launch workers.'
              : planReview
              ? 'Approval freezes this plan. Workers start only when you explicitly start execution.'
              : 'Approval applies only to this revision, integrated results and artifact evidence. Changed evidence requires another review.',
        ),
        const SizedBox(height: AleraTokens.space16),
        for (final stage in stages.cast<Map>())
          if (planReview ||
              correctionReview ||
              review.scope == 'stage:${stage['id']}') ...[
            Text(
              stage['name']! as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(stage['purpose']! as String),
            if ((stage['dependsOn']! as List).isNotEmpty)
              Text('Depends on: ${(stage['dependsOn']! as List).join(', ')}'),
            for (final frozen in tasks.cast<Map>())
              if ((frozen['task']! as Map)['stageId'] == stage['id'])
                _task(context, frozen),
            const SizedBox(height: AleraTokens.space16),
          ],
        if (!planReview || review.tasks.isNotEmpty) ...[
          Text(
            planReview
                ? 'Referenced Task Evidence'
                : correctionReview
                ? 'Current Task Evidence'
                : 'Integrated Evidence',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (planReview)
            const Text(
              'Approval also binds this prior task evidence. Changed results require another review; original tasks remain in history.',
            ),
          for (final evidence in review.tasks) ...[
            const SizedBox(height: AleraTokens.space12),
            Text(evidence['logicalId']! as String),
            if (correctionReview || planReview)
              Text('Task status: ${evidence['status']}'),
            if ((correctionReview || planReview) &&
                evidence['integrationState'] != null) ...[
              Text('Integration: ${evidence['integrationState']}'),
              for (final path in evidence['conflictPaths']! as List)
                Text(path as String, style: AleraTokens.monoCompactStyle),
              if (evidence['conflictsTruncated'] == true)
                const Text(
                  'More conflicts are available in the task inspector.',
                ),
              if (evidence['integrationError'] case final String error)
                SelectableText(error),
            ],
            SelectableText(
              evidence['resultPreview'] as String? ?? 'No text result.',
            ),
            if (evidence['resultTruncated'] == true)
              const Text(
                'Preview shortened. Inspect the task for the complete result.',
              ),
            Text(
              'Artifact Digest',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            SelectableText(
              evidence['artifactDigest'] as String? ?? 'Unavailable',
              style: AleraTokens.monoCompactStyle,
            ),
            TextButton(
              onPressed: widget.busy
                  ? null
                  : () => widget.onInspectTask(evidence['taskId']! as String),
              child: const Text('Inspect Task Evidence'),
            ),
          ],
        ],
        const SizedBox(height: AleraTokens.space16),
        AleraTextField(
          controller: _reason,
          labelText: 'Review Notes',
          hintText: 'Required when rejecting or requesting changes.',
          enabled: !widget.busy,
          minLines: 2,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
        ),
        if (widget.invalidated) ...[
          const SizedBox(height: AleraTokens.space12),
          const Text(
            'This review is no longer current. Refresh and inspect the latest evidence before deciding.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: widget.busy ? null : widget.onRefresh,
              child: const Text('Refresh Review'),
            ),
          ),
        ],
        if (widget.error case final error?) ...[
          const SizedBox(height: AleraTokens.space12),
          SelectableText(error),
        ],
        const SizedBox(height: AleraTokens.space16),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            if (!correctionReview)
              FilledButton(
                onPressed: enabled
                    ? () => widget.onDecision(
                        WorkflowHumanDecision.approve,
                        _reason.text,
                      )
                    : null,
                child: Text(planReview ? 'Approve Plan' : 'Approve Gate'),
              ),
            OutlinedButton(
              onPressed: enabled && _reason.text.trim().isNotEmpty
                  ? () => widget.onDecision(
                      WorkflowHumanDecision.requestChanges,
                      _reason.text,
                    )
                  : null,
              child: const Text('Request Changes'),
            ),
            if (!correctionReview)
              TextButton(
                onPressed: enabled && _reason.text.trim().isNotEmpty
                    ? () => widget.onDecision(
                        WorkflowHumanDecision.reject,
                        _reason.text,
                      )
                    : null,
                child: const Text('Reject'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _task(BuildContext context, Map frozen) {
    final task = frozen['task']! as Map;
    final contract = (frozen['contract']! as Map)['contract']! as Map;
    final profile =
        (widget.review.plan['profiles']! as Map)[frozen['profileId']]! as Map;
    return ExpansionTile(
      key: PageStorageKey(
        'review:${widget.review.runId}:${widget.review.revision}:${task['id']}',
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AleraTokens.space12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text(task['title']! as String),
      subtitle: Text('${task['roleId']} / ${profile['name']}'),
      children: [
        SelectableText(
          task['spec']! as String,
          key: const PageStorageKey('task-spec'),
        ),
        const SizedBox(height: AleraTokens.space8),
        Text(
          'Depends on: ${(task['dependsOn']! as List).isEmpty ? 'none' : (task['dependsOn']! as List).join(', ')}',
        ),
        if (task['correctsTaskId'] case final String corrected)
          Text('Corrects task: $corrected'),
        const SizedBox(height: AleraTokens.space12),
        Text(
          'Role Contract: ${contract['name']} / Revision ${contract['revision']}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        SelectableText(
          contract['purpose']! as String,
          key: const PageStorageKey('contract-purpose'),
        ),
        const SizedBox(height: AleraTokens.space8),
        SelectableText(
          contract['instructions']! as String,
          key: const PageStorageKey('contract-instructions'),
        ),
        for (final artifact in contract['requiredArtifacts']! as List)
          Text('Required artifact: $artifact'),
        for (final item in (contract['checklist']! as List).cast<Map>())
          Text('Check: ${item['description']}'),
      ],
    );
  }
}

String _originLabel(Map source) => switch (source['origin']) {
  'builtIn' => 'Built-in',
  'personal' => 'Personal',
  'project' => 'Project: ${source['path']}',
  _ => 'Unknown Origin',
};

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/orchestration/domain/run_snapshot.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_read_state.dart';
import 'package:flutter/material.dart';

class RunBoardDetail extends StatelessWidget {
  const RunBoardDetail({
    super.key,
    required this.snapshot,
    required this.onTask,
    required this.onBack,
    this.onOpenWorkspace,
    required this.footer,
  });
  final RunSnapshot snapshot;
  final ValueChanged<String> onTask;
  final VoidCallback onBack;
  final VoidCallback? onOpenWorkspace;
  final Widget footer;
  @override
  Widget build(BuildContext context) {
    final stages = <String?, List<RunTaskSummary>>{};
    for (final task in snapshot.tasks) {
      stages.putIfAbsent(task.stageId, () => []).add(task);
    }
    final rows = <Object>[
      for (final stage in stages.entries) ...[
        stage.key ?? 'Unassigned Stage',
        ...stage.value,
      ],
    ];
    final rowIndices = <String, int>{
      for (final (index, row) in rows.indexed)
        if (row is RunTaskSummary) row.id: index + 1,
    };
    return ListView.builder(
      key: PageStorageKey('run-detail:${snapshot.run.id}'),
      findChildIndexCallback: (key) =>
          key is ValueKey<String> ? rowIndices[key.value] : null,
      padding: const EdgeInsets.all(AleraTokens.space16),
      itemCount: rows.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _header(context);
        if (index == rows.length + 1) return footer;
        final row = rows[index - 1];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space16),
            child: Text(row, style: Theme.of(context).textTheme.titleSmall),
          );
        }
        final task = row as RunTaskSummary;
        final state = task.workflowState ?? task.status;
        return AleraActivityRow(
          key: ValueKey(task.id),
          title: task.title,
          subtitle: runBoardStatusLabel(state),
          statusColor: runBoardStatusColor(state),
          metadata: task.dependencies.isEmpty
              ? (task.dependenciesTruncated
                    ? 'Dependencies unavailable'
                    : 'No Dependencies')
              : 'Depends On: ${task.dependencies.join(', ')}${task.dependenciesTruncated ? ' (partial)' : ''}',
          onPressed: () => onTask(task.id),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final run = snapshot.run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(AleraIcons.back),
              label: const Text('All Runs'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenWorkspace,
              icon: const Icon(AleraIcons.folderOpen),
              label: const Text('Open Workspace'),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        Text('Run Overview', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AleraTokens.space12),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            AleraBadge(
              label: runBoardStatusLabel(run.status),
              foregroundColor: runBoardStatusColor(run.status),
            ),
            AleraBadge(
              label: '${run.completedCount}/${run.taskCount} Completed',
            ),
            if (run.pendingGateCount > 0)
              AleraBadge(
                label:
                    '${run.pendingGateCount} Pending ${run.pendingGateCount == 1 ? 'Gate' : 'Gates'}',
                foregroundColor: AleraTokens.warning,
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        SelectableText(
          snapshot.objective,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (snapshot.objectiveTruncated)
          const Text('The objective preview is truncated.'),
        const SizedBox(height: AleraTokens.space16),
        Text('Origin', style: Theme.of(context).textTheme.labelLarge),
        SelectableText(
          '${run.projectName ?? 'Unavailable project'} / ${run.workspaceName ?? run.workspaceId}',
        ),
        SelectableText(run.id, style: AleraTokens.monoCompactStyle),
        const SizedBox(height: AleraTokens.space8),
        Text(
          'Snapshot Revision: ${snapshot.revision}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text('Execution Policy: ${runBoardStatusLabel(run.policyStatus)}'),
        if (onOpenWorkspace == null)
          const Text('The owning workspace is unavailable on this host.'),
        const SizedBox(height: AleraTokens.space24),
        Text('Stages & Tasks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.space8),
        Text(
          '${snapshot.tasks.length} of ${run.taskCount} tasks loaded. Stage membership and dependencies are recorded by the runtime.',
        ),
        if (snapshot.tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AleraTokens.space16),
            child: Text('No tasks have been prepared for this run.'),
          ),
      ],
    );
  }
}

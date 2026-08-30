import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_read_state.dart';
import 'package:flutter/material.dart';

class RunBoardList extends StatelessWidget {
  const RunBoardList({
    super.key,
    required this.snapshot,
    this.selectedRunId,
    required this.onSelect,
    required this.filters,
    required this.footer,
    this.message,
  });
  final RunBoardSnapshot? snapshot;
  final Widget? message;
  final String? selectedRunId;
  final ValueChanged<String> onSelect;
  final Widget filters;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final entries = <Object>[
      for (final bucket in RunBoardBucket.values)
        if (snapshot?.items.any((run) => run.bucket == bucket) ?? false) ...[
          bucket,
          ...snapshot!.items.where((run) => run.bucket == bucket),
        ],
    ];
    final rowIndices = <String, int>{
      for (final (index, entry) in entries.indexed)
        if (entry is RunSummary) entry.id: index + 1,
    };
    return ListView.builder(
      key: const PageStorageKey('run-board-list'),
      findChildIndexCallback: (key) =>
          key is ValueKey<String> ? rowIndices[key.value] : null,
      itemCount: entries.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) return filters;
        if (index == entries.length + 1) {
          return message ??
              (entries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AleraTokens.space16),
                      child: Text(
                        'No runs match this view. Try clearing filters. Runs created through orchestration will appear here.',
                      ),
                    )
                  : const SizedBox.shrink());
        }
        if (index == entries.length + 2) return footer;
        final entry = entries[index - 1];
        if (entry is RunBoardBucket) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AleraTokens.space12,
              horizontal: AleraTokens.space12,
            ),
            child: Text(switch (entry) {
              RunBoardBucket.attention => 'Attention',
              RunBoardBucket.active => 'Active',
              RunBoardBucket.history => 'History',
            }, style: Theme.of(context).textTheme.titleSmall),
          );
        }
        final run = entry as RunSummary;
        return AleraActivityRow(
          key: ValueKey(run.id),
          title: run.objective.isEmpty ? run.id : run.objective,
          subtitle:
              '${runBoardStatusLabel(run.status)} · ${run.completedCount}/${run.taskCount} Tasks'
              '${run.pendingGateCount == 0 ? '' : ' · ${run.pendingGateCount} Pending ${run.pendingGateCount == 1 ? 'Gate' : 'Gates'}'}',
          metadata:
              '${run.projectName ?? 'Unavailable Project'} / ${run.workspaceName ?? run.workspaceId}',
          selected: run.id == selectedRunId,
          statusColor: run.bucket == RunBoardBucket.attention
              ? AleraTokens.warning
              : runBoardStatusColor(run.status),
          onPressed: () => onSelect(run.id),
        );
      },
    );
  }
}

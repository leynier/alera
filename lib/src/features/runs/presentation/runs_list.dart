import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';

/// The master list: filters, then Attention, Active and History groups.
class const RunsList({
  super.key,
  required final RunBoardPage? page,
  final String? selectedRunId,
  required final ValueChanged<String> onSelect,
  required final Widget filters,
  required final Widget footer,
  required final String emptyMessage,
  required final DateTime now,
  final Widget? message,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = page?.items ?? const <RunSummary>[];
    final entries = <Object>[
      for (final bucket in RunBucket.values)
        if (items.any((run) => run.bucket == bucket)) ...<Object>[
          bucket,
          ...items.where((run) => run.bucket == bucket),
        ],
    ];
    final rowIndices = <String, int>{
      for (final (index, entry) in entries.indexed)
        if (entry is RunSummary) entry.id: index + 1,
    };
    return ListView.builder(
      key: const PageStorageKey<String>('runs-list'),
      findChildIndexCallback: (key) =>
          key is ValueKey<String> ? rowIndices[key.value] : null,
      itemCount: entries.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) return filters;
        if (index == entries.length + 1) {
          return message ??
              (entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AleraTokens.space16),
                      child: Text(emptyMessage),
                    )
                  : const SizedBox.shrink());
        }
        if (index == entries.length + 2) return footer;
        final entry = entries[index - 1];
        if (entry is RunBucket) {
          final count = switch (entry) {
            RunBucket.attention => page?.counts.attention,
            RunBucket.active => page?.counts.active,
            RunBucket.history => page?.counts.history,
          };
          return AleraSectionHeader(
            label:
                '${runBucketLabel(entry)}${count == null ? '' : ' ($count)'}',
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space12,
              AleraTokens.space12,
              AleraTokens.space8,
              AleraTokens.space4,
            ),
          );
        }
        final run = entry as RunSummary;
        return RunListRow(
          key: ValueKey<String>(run.id),
          run: run,
          now: now,
          selected: run.id == selectedRunId,
          onPressed: () => onSelect(run.id),
        );
      },
    );
  }
}

String runBucketLabel(RunBucket bucket) => switch (bucket) {
  RunBucket.attention => 'Attention',
  RunBucket.active => 'Active',
  RunBucket.history => 'History',
};

/// Objective; status, progress and why it needs attention; project and
/// workspace; time since its last activity.
class const RunListRow({
  super.key,
  required final RunSummary run,
  required final DateTime now,
  required final bool selected,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = runStatusLabel(run);
    final reason = run.bucket == RunBucket.attention
        ? runAttentionLabel(run)
        : null;
    return AleraActivityRow(
      title: run.objective.isEmpty ? run.id : run.objective,
      subtitle: <String>[
        status.label,
        '${run.completedCount}/${run.taskCount}',
        ?reason,
      ].join(' · '),
      metadata:
          '${run.projectName ?? 'Unavailable Project'} / ${run.workspaceName ?? run.workspaceId}',
      trailing: runAgeLabel(run.lastActivityAt, now),
      selected: selected,
      statusColor: status.tone.foreground,
      onPressed: onPressed,
    );
  }
}

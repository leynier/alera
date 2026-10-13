import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/runs/application/run_detail_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/presentation/run_read_state.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One plan stage and its loaded tasks.
class RunStageGroup {
  RunStageGroup(this.id, this.title, this.gate);

  final String? id;
  final String title;
  final bool gate;
  final List<RunTask> tasks = <RunTask>[];
}

/// Groups tasks by stage in plan order; tasks outside the plan come last.
List<RunStageGroup> runStageGroups(List<RunTask> tasks, RunPlanView? plan) {
  final groups = <String?, RunStageGroup>{
    for (final stage in plan?.stages ?? const <RunPlanStage>[])
      stage.id: RunStageGroup(stage.id, stage.label, stage.gate),
  };
  for (final task in tasks) {
    groups
        .putIfAbsent(
          task.stageId,
          () => RunStageGroup(
            task.stageId,
            task.stageId ?? 'Unassigned Stage',
            false,
          ),
        )
        .tasks
        .add(task);
  }
  return <RunStageGroup>[
    for (final group in groups.values)
      if (group.tasks.isNotEmpty) group,
  ];
}

/// The Tasks tab without a selected task: one header per stage with its
/// progress and gate, then a row per task.
class const RunTasksTab({
  super.key,
  required final RunSnapshot snapshot,
  required final bool loadingMore,
  final Object? pageError,
  required final VoidCallback onMore,
  required final VoidCallback onRefresh,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = snapshot.run;
    if (snapshot.tasks.isEmpty) {
      return AleraEmptyState(
        icon: AleraIcons.workspaceChildren,
        title: 'No Tasks Yet',
        message: run.status == 'planning'
            ? 'Tasks appear once the coordinator proposes a plan.'
            : 'This run has no tasks.',
      );
    }
    final plan = snapshot.plan;
    final view = plan == null
        ? null
        : ref
              .watch(
                runPlanProvider(
                  run.id,
                  revision: plan.revision,
                  state: plan.state,
                ),
              )
              .value;
    final navigation = ref.read(activityNavigationProvider.notifier);
    final now = ref.watch(runClockProvider)();
    final rows = <Object>[
      for (final group in runStageGroups(snapshot.tasks, view)) ...<Object>[
        group,
        ...group.tasks,
      ],
    ];
    return ListView.builder(
      key: PageStorageKey<String>('run-tasks:${run.id}'),
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return RunPageFooter(
            hasMore: snapshot.nextTaskId != null,
            loading: loadingMore,
            error: pageError,
            onMore: onMore,
            onRefresh: onRefresh,
            label: 'Load More Tasks',
          );
        }
        final row = rows[index];
        if (row is RunStageGroup) {
          return AleraSectionHeader(
            key: ValueKey<String>('stage:${row.id}'),
            label: _stageLabel(row, run.isolated),
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space12,
              AleraTokens.space12,
              AleraTokens.space8,
              AleraTokens.space4,
            ),
          );
        }
        final task = row as RunTask;
        final status = taskStatusLabel(taskDisplayState(task));
        return AleraActivityRow(
          key: ValueKey<String>(task.id),
          title: task.title,
          trailing: _taskAge(task, now),
          subtitle: <String>[
            status.label,
            ?task.profile,
            if (task.attempt != null) 'Attempt ${task.attempt!.attempt}',
          ].join(' · '),
          metadata: <String>[
            task.logicalId ?? task.id,
            if (task.dependencies.isNotEmpty)
              'Depends On ${task.dependencies.join(', ')}',
          ].join(' · '),
          statusColor: status.tone.foreground,
          onPressed: () => navigation.selectTask(task.id),
        );
      },
    );
  }

  String? _taskAge(RunTask task, DateTime now) {
    final age = runAgeLabel(task.updatedAt, now);
    return age.isEmpty ? null : age;
  }

  String _stageLabel(RunStageGroup group, bool isolated) {
    final done = group.tasks
        .where(
          (task) => isolated
              ? task.integration?.state == 'integrated' ||
                    task.attemptState == 'integrated'
              : task.status == 'completed',
        )
        .length;
    final gates = snapshot.pendingGates.where(
      (gate) => gate.kind == RunGateKind.stage && gate.scope == group.id,
    );
    final gate = gates.isEmpty
        ? (group.gate ? 'Stage gate' : null)
        : gates.first.due
        ? 'Gate pending'
        : 'Gate waiting for evidence';
    return <String>[
      group.title,
      '$done/${group.tasks.length} ${isolated ? 'Integrated' : 'Completed'}',
      ?gate,
    ].join(' · ');
  }
}

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_tab_strip.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/runs/application/run_detail_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/presentation/run_overview_tab.dart';
import 'package:alera/src/features/runs/presentation/run_read_state.dart';
import 'package:alera/src/features/runs/presentation/run_resources_tab.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:alera/src/features/runs/presentation/run_task_inspector.dart';
import 'package:alera/src/features/runs/presentation/run_tasks_tab.dart';
import 'package:alera/src/features/runs/presentation/run_timeline_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A selected run: its header and the Overview, Tasks, Timeline and
/// Resources tabs. Selecting a run never changes the active workspace.
class const RunDetailPage({super.key, required final String runId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = runDetailProvider(runId);
    final page = ref.watch(provider);
    final data = page.hasError ? null : page.value;
    if (data == null) {
      return RunReadState(
        error: page.error,
        subject: 'this run',
        onRefresh: () => ref.invalidate(provider),
      );
    }
    final snapshot = data.data;
    final location = ref.watch(
      activityNavigationProvider.select((value) => value.runs),
    );
    final navigation = ref.read(activityNavigationProvider.notifier);
    final isolated = snapshot.run.isolated;
    final tab = !isolated && location.tab == RunDetailTab.resources
        ? RunDetailTab.overview
        : location.tab;
    final run = snapshot.run;
    final body = switch (tab) {
      RunDetailTab.overview => RunOverviewTab(
        key: ValueKey<String>('overview:$runId'),
        snapshot: snapshot,
        focusGateId: location.gateId,
        focusSequence: location.gateFocusSequence,
      ),
      RunDetailTab.tasks when location.taskId != null => RunTaskInspector(
        key: ValueKey<String>('task:${location.taskId}'),
        runId: runId,
        taskId: location.taskId!,
      ),
      RunDetailTab.tasks => RunTasksTab(
        key: ValueKey<String>('tasks:$runId'),
        snapshot: snapshot,
        loadingMore: data.loadingMore,
        pageError: data.pageError,
        onMore: () => ref.read(provider.notifier).loadMoreTasks(),
        onRefresh: () => ref.invalidate(provider),
      ),
      RunDetailTab.timeline => RunTimelineTab(
        key: ValueKey<String>('timeline:$runId'),
        runId: runId,
        filter: location.timelineFilter,
      ),
      RunDetailTab.resources => RunResourcesTab(
        key: ValueKey<String>('resources:$runId'),
        snapshot: snapshot,
      ),
    };
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _RunHeader(snapshot: snapshot),
        AleraTabStrip<RunDetailTab>(
          selected: tab,
          onSelected: (value) => value == RunDetailTab.tasks
              ? navigation.selectTask(null)
              : navigation.showRunTab(value),
          items: <AleraTabStripItem<RunDetailTab>>[
            for (final value in RunDetailTab.values)
              if (value != RunDetailTab.resources || isolated)
                AleraTabStripItem<RunDetailTab>(
                  value: value,
                  label: value.label,
                  badge: switch (value) {
                    RunDetailTab.tasks =>
                      '${run.completedCount}/${run.taskCount}',
                    RunDetailTab.resources => _resourceBadge(
                      snapshot.resourceCount,
                    ),
                    _ => null,
                  },
                ),
          ],
        ),
        Expanded(
          child: KeyedSubtree(key: ValueKey<RunDetailTab>(tab), child: body),
        ),
      ],
    );
  }
}

/// Retained worktrees and branches; nothing once a cleanup retired them all
/// or when an older host does not report the count.
String? _resourceBadge(int? count) =>
    count == null || count <= 0 ? null : '$count';

class const _RunHeader({required final RunSnapshot snapshot})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final run = snapshot.run;
    final status = runStatusLabel(run);
    final now = ref.watch(runClockProvider)();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space12,
        AleraTokens.space16,
        AleraTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          Text(
            run.objective.isEmpty ? run.id : run.objective,
            maxLines: 2,
            overflow: .ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space4,
            crossAxisAlignment: .center,
            children: <Widget>[
              AleraBadge(label: status.label, tone: status.tone),
              Text(
                <String>[
                  '${run.projectName ?? 'Unavailable Project'} / ${run.workspaceName ?? run.workspaceId}',
                  runIsolationLabel(run.isolation),
                  runAgeLabel(run.lastActivityAt, now),
                ].where((part) => part.isNotEmpty).join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

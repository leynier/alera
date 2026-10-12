import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_location.dart';
import 'package:alera/src/features/runs/application/run_board_pages.dart';
import 'package:alera/src/features/runs/application/run_detail_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/application/run_timeline_page.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/presentation/new_run_dialog.dart';
import 'package:alera/src/features/runs/presentation/run_detail_page.dart';
import 'package:alera/src/features/runs/presentation/run_read_state.dart';
import 'package:alera/src/features/runs/presentation/runs_filters.dart';
import 'package:alera/src/features/runs/presentation/runs_list.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reloads what the Runs section shows for [location].
void refreshRuns(WidgetRef ref, RunsLocation location) {
  ref.invalidate(runsListProvider(location));
  ref.invalidate(runBoardAttentionProvider);
  final runId = location.runId;
  if (runId == null) return;
  ref.invalidate(runDetailProvider(runId));
  ref.invalidate(runTimelineProvider(runId, location.timelineFilter));
  ref.invalidate(runGateDetailProvider);
  ref.invalidate(runPlanProvider);
  final taskId = location.taskId;
  if (taskId != null) {
    ref.invalidate(runTaskInspectionPageProvider(runId, taskId));
  }
}

RunBoardListPageProvider runsListProvider(RunsLocation location) =>
    runBoardListPageProvider(
      projectId: location.projectId,
      workspaceId: location.workspaceId,
      search: location.search,
      bucket: location.bucket,
    );

/// The Runs section of Activity: the run list beside the selected run.
class const RunsSection({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(
      activityNavigationProvider.select((value) => value.runs),
    );
    final navigation = ref.read(activityNavigationProvider.notifier);
    final provider = runsListProvider(location);
    final page = ref.watch(provider);
    final data = page.hasError ? null : page.value;
    final workbench = ref.watch(workbenchControllerProvider);
    final now = ref.watch(runClockProvider)();
    final projects = <AleraDropdownFieldEntry<String?>>[
      const AleraDropdownFieldEntry<String?>(
        value: null,
        label: 'All Projects',
      ),
      for (final project in workbench.projects)
        AleraDropdownFieldEntry<String?>(
          value: project.id,
          label: project.name,
        ),
      if (location.projectId != null &&
          !workbench.projects.any((item) => item.id == location.projectId))
        AleraDropdownFieldEntry<String?>(
          value: location.projectId,
          label: 'Unavailable Project',
        ),
    ];
    final allWorkspaces = workbench.workspacesByProject.values.expand(
      (items) => items,
    );
    final workspaces = <AleraDropdownFieldEntry<String?>>[
      const AleraDropdownFieldEntry<String?>(
        value: null,
        label: 'All Workspaces',
      ),
      for (final workspace in allWorkspaces)
        if (location.projectId == null ||
            workspace.projectId == location.projectId)
          AleraDropdownFieldEntry<String?>(
            value: workspace.id,
            label: workspace.name,
          ),
      if (location.workspaceId != null &&
          !allWorkspaces.any((item) => item.id == location.workspaceId))
        AleraDropdownFieldEntry<String?>(
          value: location.workspaceId,
          label: 'Unavailable Workspace',
        ),
    ];
    final filtered = location.filtered;
    final updateRequired = page.error is RunsUpdateRequired;
    Widget master({bool showError = true}) => RunsList(
      page: data?.data,
      now: now,
      selectedRunId: location.runId,
      onSelect: navigation.selectRun,
      emptyMessage: filtered
          ? 'No runs match these filters. Clear or adjust them to see other runs.'
          : 'No runs yet.',
      filters: RunsFilters(
        location: location,
        projects: projects,
        workspaces: workspaces,
        counts: data?.data.counts,
        onSearch: navigation.searchRuns,
        onProject: navigation.filterRunProject,
        onWorkspace: navigation.filterRunWorkspace,
        onBucket: navigation.filterRunBucket,
        onClear: navigation.clearRunFilters,
      ),
      message: data == null
          ? showError
                ? RunReadState(
                    error: page.error,
                    onRefresh: () => ref.invalidate(provider),
                  )
                : Padding(
                    padding: const EdgeInsets.all(AleraTokens.space16),
                    child: Text(
                      page.hasError
                          ? updateRequired
                                ? 'This host cannot load runs. Update the runtime host, then reconnect.'
                                : 'The run list is unavailable. Reconnect or refresh to retry.'
                          : 'Loading runs…',
                    ),
                  )
          : null,
      footer: RunPageFooter(
        hasMore: data?.data.nextCursor != null,
        loading: data?.loadingMore ?? false,
        error: data?.pageError,
        onMore: () => ref.read(provider.notifier).loadMore(),
        onRefresh: () => ref.invalidate(provider),
        label: 'Load More Runs',
      ),
    );
    final empty = data?.data.items.isEmpty ?? false;
    final runId = location.runId;
    final Widget detail = runId != null
        ? RunDetailPage(key: ValueKey<String>(runId), runId: runId)
        : data == null
        ? RunReadState(
            error: page.error,
            onRefresh: () => ref.invalidate(provider),
          )
        : _NoSelection(empty: empty, filtered: filtered);
    return FocusTraversalGroup(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (constraints.maxWidth <
              AleraTokens.wideContentBreakpoint * scale) {
            if (runId == null) return master();
            return Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                TextButton.icon(
                  key: const ValueKey<String>('runsBack'),
                  onPressed: () => navigation.selectRun(null),
                  icon: const Icon(AleraIcons.back, size: AleraTokens.iconMd),
                  label: const Text('Back To Runs'),
                ),
                Expanded(child: detail),
              ],
            );
          }
          return AleraMasterDetail(
            masterTitle: 'Runs',
            masterWidth: AleraTokens.sidebarDefaultWidth,
            masterMaxWidth: AleraTokens.masterDetailMaxWidth,
            master: master(showError: false),
            detail: detail,
          );
        },
      ),
    );
  }
}

class const _NoSelection({
  required final bool empty,
  required final bool filtered,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: AleraEmptyState(
          icon: AleraIcons.workspaceChildren,
          title: empty
              ? filtered
                    ? 'No Matching Runs'
                    : 'No Runs Yet'
              : 'Select a Run',
          message: empty
              ? filtered
                    ? 'Clear or adjust your filters to see other runs.'
                    : 'Create a run to let a coordinator plan and dispatch work. Your active workspace stays unchanged.'
              : 'Inspect progress, gates, tasks and the timeline. Selecting a run does not change your active workspace.',
          action: empty && !filtered
              ? FilledButton.icon(
                  key: const ValueKey<String>('runsEmptyNewRun'),
                  onPressed: () => showNewRunDialog(context),
                  icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
                  label: const Text('New Run'),
                )
              : null,
        ),
      ),
    ),
  );
}

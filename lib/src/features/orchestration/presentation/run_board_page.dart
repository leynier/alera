import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/application/run_board_pages.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_detail.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_filters.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_list.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_read_state.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_workspace_actions.dart';
import 'package:alera/src/features/orchestration/presentation/run_task_inspector.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_retry_control.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_page.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_review_page.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_correction_page.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_run_control_section.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_new_run_page.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_proposal_page.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RunBoardPage extends ConsumerWidget {
  const RunBoardPage({super.key, this.onReturnToWorkspace});
  final VoidCallback? onReturnToWorkspace;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(runBoardNavigationProvider);
    final navigation = ref.read(runBoardNavigationProvider.notifier);
    final provider = runBoardListPageProvider(
      projectId: location.projectId,
      workspaceId: location.workspaceId,
      search: location.search,
      bucket: location.bucket,
    );
    final page = ref.watch(provider);
    final data = page.hasError ? null : page.value;
    final workbench = ref.watch(workbenchControllerProvider);
    final projects = [
      const AleraDropdownFieldEntry<String?>(
        value: null,
        label: 'All Projects',
      ),
      for (final project in workbench.projects)
        AleraDropdownFieldEntry<String?>(
          value: project.id,
          label: project.name,
        ),
    ];
    final workspaces = [
      const AleraDropdownFieldEntry<String?>(
        value: null,
        label: 'All Workspaces',
      ),
      for (final workspace in workbench.workspacesByProject.values.expand(
        (items) => items,
      ))
        if (location.projectId == null ||
            workspace.projectId == location.projectId)
          AleraDropdownFieldEntry<String?>(
            value: workspace.id,
            label: workspace.name,
          ),
    ];
    if (location.projectId != null &&
        !projects.any((item) => item.value == location.projectId)) {
      projects.add(
        AleraDropdownFieldEntry(
          value: location.projectId,
          label: 'Unavailable Project',
        ),
      );
    }
    if (location.workspaceId != null &&
        !workspaces.any((item) => item.value == location.workspaceId)) {
      workspaces.add(
        AleraDropdownFieldEntry(
          value: location.workspaceId,
          label: 'Unavailable Workspace',
        ),
      );
    }
    final filtered =
        location.projectId != null ||
        location.workspaceId != null ||
        location.search.isNotEmpty ||
        location.bucket != null;
    Widget master({bool showError = true}) => RunBoardList(
      snapshot: data?.data,
      selectedRunId: location.runId,
      onSelect: navigation.selectRun,
      emptyMessage: filtered
          ? 'No runs match these filters. Clear or adjust them to see other runs.'
          : 'No runs yet. Runs created through orchestration will appear here.',
      filters: RunBoardFilters(
        location: location,
        projects: projects,
        workspaces: workspaces,
        counts: data?.data.counts,
        onSearch: navigation.search,
        onProject: navigation.selectProject,
        onWorkspace: navigation.selectWorkspace,
        onBucket: navigation.selectBucket,
        onClear: navigation.clearFilters,
      ),
      message: data == null
          ? showError
                ? RunBoardReadState(
                    error: page.error,
                    onRefresh: () => ref.invalidate(provider),
                  )
                : Padding(
                    padding: const EdgeInsets.all(AleraTokens.space16),
                    child: Text(
                      page.hasError
                          ? page.error is RunBoardUpdateRequired
                                ? 'This host cannot load runs. Update the runtime host, then reconnect.'
                                : 'The run list is unavailable. Reconnect or refresh to retry.'
                          : 'Loading runs...',
                    ),
                  )
          : null,
      footer: RunBoardPageFooter(
        hasMore: data?.data.nextCursor != null,
        loading: data?.loadingMore ?? false,
        error: data?.pageError,
        onMore: () => ref.read(provider.notifier).loadMore(),
        onRefresh: () => ref.invalidate(provider),
        label: 'Load More Runs',
      ),
    );
    final empty = data?.data.items.isEmpty ?? false;
    final detail = location.newRun
        ? WorkflowNewRunPage(
            onCreated: navigation.selectProposal,
            onBack: () => navigation.selectRun(null),
          )
        : location.proposalId != null
        ? WorkflowProposalPage(
            key: ValueKey(location.proposalId),
            id: location.proposalId!,
            onBack: () => navigation.selectRun(null),
            onOpenRun: navigation.selectRun,
          )
        : location.runId == null
        ? data == null
              ? RunBoardReadState(
                  error: page.error,
                  onRefresh: () => ref.invalidate(provider),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
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
                                  : 'Orchestration runs will appear here once they are created. Your active workspace remains unchanged.'
                            : 'Inspect progress, tasks and evidence across projects. Selecting a run does not change your active workspace.',
                      ),
                    ),
                  ),
                )
        : _RunBoardSelection(
            key: ValueKey(location.runId),
            runId: location.runId!,
            taskId: location.taskId,
          );
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AleraTokens.space12,
              runSpacing: AleraTokens.space8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const AleraAppMenuButton(),
                Text(
                  'Run Board',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilledButton(
                  onPressed: navigation.createRun,
                  child: const Text('New Run'),
                ),
                TextButton.icon(
                  onPressed: onReturnToWorkspace ?? navigation.close,
                  icon: const Icon(AleraIcons.back),
                  label: const Text('Return to Workspace'),
                ),
                IconButton(
                  tooltip: 'Refresh Run Board',
                  icon: const Icon(AleraIcons.refresh),
                  onPressed: () {
                    ref.invalidate(provider);
                    if (location.runId != null) {
                      ref.invalidate(runTaskPageProvider(location.runId!));
                    }
                    if (location.runId != null && location.taskId != null) {
                      ref.invalidate(
                        runTaskInspectionPageProvider(
                          location.runId!,
                          location.taskId!,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  if (constraints.maxWidth <
                      AleraTokens.wideContentBreakpoint * scale) {
                    return location.runId == null &&
                            !location.newRun &&
                            location.proposalId == null
                        ? master()
                        : detail;
                  }
                  return AleraMasterDetail(
                    masterTitle: 'Runs',
                    masterWidth: AleraTokens.sidebarDefaultWidth,
                    master: master(showError: false),
                    detail: detail,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunBoardSelection extends ConsumerWidget {
  const _RunBoardSelection({super.key, required this.runId, this.taskId});
  final String runId;
  final String? taskId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.read(runBoardNavigationProvider.notifier);
    final selectedTask = taskId;
    final correctionRevision = ref.watch(
      runBoardNavigationProvider.select(
        (location) => location.correctionRevision,
      ),
    );
    if (correctionRevision != null) {
      return WorkflowCorrectionPage(
        key: ValueKey('correction:$runId:$correctionRevision'),
        runId: runId,
        revision: correctionRevision,
        onBack: () => navigation.review(null),
        onCreated: navigation.selectProposal,
      );
    }
    if (selectedTask != null) {
      final provider = runTaskInspectionPageProvider(runId, selectedTask);
      final page = ref.watch(provider);
      final data = page.hasError ? null : page.value;
      if (data == null) {
        return _recoverable(
          context,
          page.error,
          () => ref.invalidate(provider),
          () => navigation.selectTask(null),
        );
      }
      final task = data.data.inspection;
      final executionWorkspaceId =
          task.workflow?.executionWorkspaceId ?? task.workspaceId;
      return RunTaskInspector(
        task: task,
        retryControl:
            task.workflow?.canRetry == true &&
                task.workflow?.planRevision != null
            ? WorkflowRetryControl(
                key: ValueKey('retry:$selectedTask:$executionWorkspaceId'),
                runId: runId,
                taskId: selectedTask,
                revision: task.workflow!.planRevision!,
                workspaceId: executionWorkspaceId,
                onPrepared: () => ref.invalidate(provider),
              )
            : null,
        history: data.data.history,
        onBack: () => navigation.selectTask(null),
        onOpenWorkspace: runBoardWorkspaceAction(
          context,
          ref,
          executionWorkspaceId,
          RunBoardWorkspaceAction.workspace,
        ),
        onOpenTerminal: runBoardWorkspaceAction(
          context,
          ref,
          executionWorkspaceId,
          RunBoardWorkspaceAction.terminal,
          terminalHandle: task.terminalHandle,
        ),
        onOpenDiff: runBoardWorkspaceAction(
          context,
          ref,
          executionWorkspaceId,
          RunBoardWorkspaceAction.diff,
          committedResult: task.workflow != null && task.status == 'completed',
          resultBaseSha: task.workflow?.baseSha,
          resultCompletionSha: task.workflow?.completionSha,
        ),
        footer: RunBoardPageFooter(
          hasMore: data.data.nextCursor != null,
          loading: data.loadingMore,
          error: data.pageError,
          onMore: () => ref.read(provider.notifier).loadMore(),
          onRefresh: () => ref.invalidate(provider),
          label: 'Load More History',
        ),
      );
    }
    final provider = runTaskPageProvider(runId);
    final page = ref.watch(provider);
    final data = page.hasError ? null : page.value;
    if (data == null) {
      return _recoverable(
        context,
        page.error,
        () => ref.invalidate(provider),
        () => navigation.selectRun(null),
      );
    }
    final reviewScope = ref.watch(
      runBoardNavigationProvider.select((location) => location.reviewScope),
    );
    final workflowRevision = data.data.run.workflowRevision;
    final cleanup = ref.watch(
      runBoardNavigationProvider.select(
        (location) => (location.cleanupOpen, location.cleanupId),
      ),
    );
    if (cleanup.$1 && workflowRevision != null) {
      return WorkflowCleanupPage(
        key: ValueKey('cleanup:$runId'),
        runId: runId,
        initialCleanupId: cleanup.$2,
        allowPrepare: {
          'completed',
          'cancelled',
        }.contains(data.data.run.workflowStatus),
        onBack: navigation.closeCleanup,
        onSelected: navigation.openCleanup,
      );
    }
    if (reviewScope != null && workflowRevision != null) {
      return WorkflowReviewPage(
        key: ValueKey('review:$runId:$reviewScope'),
        runId: runId,
        revision: workflowRevision,
        scope: reviewScope,
        onBack: () => navigation.review(null),
        onInspectTask: navigation.selectTask,
      );
    }
    return RunBoardDetail(
      snapshot: data.data,
      onCleanup: workflowRevision == null ? null : navigation.openCleanup,
      workflowControls: workflowRevision == null
          ? null
          : WorkflowRunControlSection(
              key: ValueKey('controls:$runId:$workflowRevision'),
              runId: runId,
              revision: workflowRevision,
              onReview: navigation.review,
              onCorrection: () =>
                  navigation.prepareCorrection(workflowRevision),
            ),
      onReviewPlan:
          workflowRevision != null && data.data.run.workflowStatus == 'prepared'
          ? () => navigation.review('plan')
          : null,
      onTask: navigation.selectTask,
      onBack: () => navigation.selectRun(null),
      onOpenWorkspace: runBoardWorkspaceAction(
        context,
        ref,
        data.data.run.workspaceId,
        RunBoardWorkspaceAction.workspace,
      ),
      footer: RunBoardPageFooter(
        hasMore: data.data.nextTaskId != null,
        loading: data.loadingMore,
        error: data.pageError,
        onMore: () => ref.read(provider.notifier).loadMore(),
        onRefresh: () => ref.invalidate(provider),
        label: 'Load More Tasks',
      ),
    );
  }

  Widget _recoverable(
    BuildContext context,
    Object? error,
    VoidCallback refresh,
    VoidCallback back,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: back,
        icon: const Icon(AleraIcons.back),
        label: const Text('Back'),
      ),
      Expanded(
        child: RunBoardReadState(error: error, onRefresh: refresh),
      ),
    ],
  );
}

import 'dart:async';

import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_providers.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/pull_requests/infra/runtime_pull_request_watch_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:logging/logging.dart';

part 'pull_request_agent_watch_providers.g.dart';
part 'pull_request_agent_watch_persistence.dart';

@Riverpod(keepAlive: true)
RuntimePullRequestWatchRepository pullRequestAgentWatchRepository(Ref ref) {
  return RuntimePullRequestWatchRepository(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
class PullRequestAgentWatchController extends _$PullRequestAgentWatchController
    with _PullRequestAgentWatchPersistence {
  final Set<String> _inFlight = <String>{};
  PullRequestAgentWatchRecords _hostRecords =
      const PullRequestAgentWatchRecords();
  Timer? _timer;

  @override
  Map<String, PullRequestAgentWatchSession> build() {
    ref.onDispose(() {
      _timer?.cancel();
      _inFlight.clear();
      _dirty.clear();
    });
    final subscription = ref
        .watch(pullRequestAgentWatchRepositoryProvider)
        .watchSnapshot()
        .listen(
          _applyHostRecords,
          onError: (Object error, StackTrace stack) =>
              Logger('PullRequestAgentWatch')
                  .warning('Could not refresh runtime watches', error, stack),
        );
    ref.onDispose(subscription.cancel);
    ref.listen<Set<String>>(
      workbenchControllerProvider.select(
        (workbench) => <String>{
          for (final workspaces in workbench.workspacesByProject.values)
            for (final workspace in workspaces) workspace.id,
        },
      ),
      (previous, next) {
        if (previous == null) {
          return;
        }
        for (final workspaceId in state.keys.toList(growable: false)) {
          if (!next.contains(workspaceId)) {
            _remove(workspaceId, detach: false, persist: false);
          }
        }
        _reconcileHost();
      },
    );
    return const <String, PullRequestAgentWatchSession>{};
  }

  PullRequestAgentWatchSession? sessionFor(String workspaceId) =>
      state[workspaceId];

  Future<void> start({
    required WorkspacePullRequestScope scope,
    required int reviewNumber,
    required PullRequestAgentWatchMode mode,
    required AgentTaskDispatchBinding binding,
    PullRequestAgentWatchScope watchScope = PullRequestAgentWatchScope.defaults,
    PullRequestAgentWatchDispatchMark? lastDispatch,
  }) async {
    final repository = ref.read(pullRequestAgentWatchRepositoryProvider);
    if (await repository.supportsExecution() &&
        ref
                .read(workspacePullRequestControllerProvider(scope))
                .asData
                ?.value
                .review
                ?.provider ==
            GitHostingProvider.github) {
      await repository.upsert(
        PullRequestAgentWatchRecord.fromSession(
          PullRequestAgentWatchSession(
            workspaceId: scope.workspaceId,
            reviewNumber: reviewNumber,
            mode: mode,
            binding: binding,
            scope: scope,
            watchScope: watchScope,
          ),
        ),
      );
      await _hydrateFromHost();
      return;
    }
    final existing = state[scope.workspaceId];
    if (existing == null) {
      ref
          .read(workspacePullRequestControllerProvider(scope).notifier)
          .attachWatcher();
    }
    state = <String, PullRequestAgentWatchSession>{
      ...state,
      scope.workspaceId: PullRequestAgentWatchSession(
        workspaceId: scope.workspaceId,
        reviewNumber: reviewNumber,
        mode: mode,
        binding: binding,
        scope: scope,
        watchScope: watchScope,
        lastDispatch: lastDispatch,
      ),
    };
    _ensureTimer();
    _persist(state[scope.workspaceId]!);
    unawaited(_evaluate(scope.workspaceId));
  }

  Future<void> stop(String workspaceId) async {
    final repository = ref.read(pullRequestAgentWatchRepositoryProvider);
    if (await repository.supportsExecution()) {
      try {
        await repository.remove(workspaceId);
        await _hydrateFromHost();
      } on Object catch (error) {
        AleraToast.publish(
          message: 'Could not stop watching. $error',
          tone: .error,
        );
      }
      return;
    }
    _remove(workspaceId, detach: true, persist: true);
  }

  void onPanelState(String workspaceId, WorkspacePullRequestState? panel) {
    unawaited(_evaluate(workspaceId, panel: panel));
  }

  void _remove(
    String workspaceId, {
    required bool detach,
    required bool persist,
  }) {
    final session = state[workspaceId];
    if (session == null) {
      return;
    }
    if (detach) {
      ref
          .read(workspacePullRequestControllerProvider(session.scope).notifier)
          .detachWatcher();
    }
    final next = Map<String, PullRequestAgentWatchSession>.from(state)
      ..remove(workspaceId);
    state = Map<String, PullRequestAgentWatchSession>.unmodifiable(next);
    if (state.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
    if (persist) {
      _persistStop(workspaceId);
    }
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      for (final workspaceId in state.keys.toList(growable: false)) {
        unawaited(_evaluate(workspaceId));
      }
    });
  }

  Future<void> _evaluate(
    String workspaceId, {
    WorkspacePullRequestState? panel,
  }) async {
    final session = state[workspaceId];
    if (session == null || !_inFlight.add(workspaceId)) {
      return;
    }
    try {
      final snapshot = _snapshotFor(session, panel: panel);
      if ((snapshot?.review == null ||
              snapshot?.review?.provider == GitHostingProvider.github) &&
          await ref
              .read(pullRequestAgentWatchRepositoryProvider)
              .supportsExecution()) {
        return;
      }
      final evaluation = evaluatePullRequestAgentWatch(
        session: session,
        snapshot: snapshot,
      );
      switch (evaluation.action) {
        case PullRequestAgentWatchAction.none:
          return;
        case PullRequestAgentWatchAction.stop:
          _remove(workspaceId, detach: true, persist: true);
          return;
        case PullRequestAgentWatchAction.dispatch:
          await _dispatch(session, evaluation);
        case PullRequestAgentWatchAction.merge:
          await _merge(session, evaluation.headSha);
      }
    } finally {
      _inFlight.remove(workspaceId);
    }
  }

  PullRequestAgentWatchSnapshot? _snapshotFor(
    PullRequestAgentWatchSession session, {
    WorkspacePullRequestState? panel,
  }) {
    if (panel != null) {
      return PullRequestAgentWatchSnapshot(
        review: panel.review,
        checksRollup: panel.checksRollup,
        comments: panel.comments,
        commentsComplete: panel.commentsComplete,
      );
    }
    final async = ref.read(
      workspacePullRequestControllerProvider(session.scope),
    );
    final current = async.asData?.value;
    if (current == null) {
      return const PullRequestAgentWatchSnapshot(loaded: false);
    }
    return PullRequestAgentWatchSnapshot(
      review: current.review,
      checksRollup: current.checksRollup,
      comments: current.comments,
      commentsComplete: current.commentsComplete,
    );
  }

  Future<void> _dispatch(
    PullRequestAgentWatchSession session,
    PullRequestAgentWatchEvaluation evaluation,
  ) async {
    final review = ref
        .read(workspacePullRequestControllerProvider(session.scope))
        .asData
        ?.value
        .review;
    final result = await completeAgentTaskDispatch(
      request: AgentTaskDispatchRequest(
        workspaceId: session.workspaceId,
        prompt: pullRequestAgentWatchPrompt(
          reviewNumber: session.reviewNumber,
          concerns: evaluation.concerns,
          baseBranch: review?.baseBranch,
        ),
      ),
      binding: session.binding,
      service: readAgentTaskDispatchServiceFromRef(
        ref,
        workspaceId: session.workspaceId,
      ),
      // Timer and panel-state follow-ups must not steal the visible workspace.
      activate: false,
    );
    final latest = state[session.workspaceId];
    if (latest == null) {
      return;
    }
    final next = pullRequestAgentWatchAfterDispatch(
      session: latest,
      result: result,
      concerns: evaluation.concerns,
      headSha: evaluation.headSha,
    );
    if (identical(next, latest)) {
      return;
    }
    state = <String, PullRequestAgentWatchSession>{
      ...state,
      session.workspaceId: next,
    };
    _persist(next);
  }

  Future<void> _merge(
    PullRequestAgentWatchSession session,
    String? headSha,
  ) async {
    final panel = ref
        .read(workspacePullRequestControllerProvider(session.scope))
        .asData
        ?.value;
    final method = _preferredMergeMethod(panel?.mergeMethods ?? const []);
    if (method == null) {
      AleraToast.publish(
        message: 'Watch, Fix and Merge could not find a merge method.',
        tone: .error,
      );
      return;
    }
    final merged = await ref
        .read(workspacePullRequestControllerProvider(session.scope).notifier)
        .mergeReview(method);
    final latest = state[session.workspaceId];
    if (latest == null) {
      return;
    }
    final next = pullRequestAgentWatchAfterMerge(
      session: latest,
      merged: merged,
      headSha: headSha,
    );
    if (identical(next, latest)) {
      return;
    }
    state = <String, PullRequestAgentWatchSession>{
      ...state,
      session.workspaceId: next,
    };
    _persist(next);
  }

  ReviewMergeMethod? _preferredMergeMethod(List<ReviewMergeMethod> methods) {
    return preferredReviewMergeMethod(methods);
  }

  Future<void> _hydrateFromHost() async {
    try {
      final repository = ref.read(pullRequestAgentWatchRepositoryProvider);
      if (!await repository.isSupported()) {
        _hostRecords = const PullRequestAgentWatchRecords();
        return;
      }
      _applyHostRecords(
        PullRequestAgentWatchRecords(
          supported: true,
          byWorkspace: await repository.listAll(),
        ),
      );
    } on Object {
      // Older or unreachable hosts keep whatever the UI started locally.
    }
  }

  void _applyHostRecords(PullRequestAgentWatchRecords records) {
    _hostRecords = records;
    _reconcileHost();
  }

  void _reconcileHost() {
    if (!_hostRecords.supported) {
      return;
    }
    final next = Map<String, PullRequestAgentWatchSession>.from(state);
    var changed = false;
    for (final record in _hostRecords.byWorkspace.values) {
      if (_dirty.contains(record.workspaceId)) {
        continue;
      }
      final scope = _scopeFor(record.workspaceId);
      if (scope == null) {
        continue;
      }
      final existing = next[record.workspaceId];
      if (existing != null && _sameWatch(existing, record)) {
        continue;
      }
      if (existing == null) {
        ref
            .read(workspacePullRequestControllerProvider(scope).notifier)
            .attachWatcher();
      }
      next[record.workspaceId] = PullRequestAgentWatchSession(
        workspaceId: record.workspaceId,
        reviewNumber: record.reviewNumber,
        mode: record.mode,
        binding: record.binding,
        scope: scope,
        watchScope: record.watchScope,
        lastDispatch: record.lastDispatch,
        lastMergedHeadSha: record.lastMergedHeadSha,
      );
      changed = true;
    }
    for (final workspaceId in next.keys.toList(growable: false)) {
      if (_dirty.contains(workspaceId) ||
          _hostRecords.byWorkspace.containsKey(workspaceId)) {
        continue;
      }
      final session = next.remove(workspaceId);
      if (session == null) {
        continue;
      }
      ref
          .read(workspacePullRequestControllerProvider(session.scope).notifier)
          .detachWatcher();
      changed = true;
    }
    if (!changed) {
      return;
    }
    state = Map<String, PullRequestAgentWatchSession>.unmodifiable(next);
    if (state.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _ensureTimer();
    for (final workspaceId in state.keys) {
      unawaited(_evaluate(workspaceId));
    }
  }

  bool _sameWatch(
    PullRequestAgentWatchSession session,
    PullRequestAgentWatchRecord record,
  ) {
    return session.reviewNumber == record.reviewNumber &&
        session.mode == record.mode &&
        session.watchScope == record.watchScope &&
        session.binding.tabId == record.tabId &&
        session.binding.profileId == record.profileId &&
        session.lastMergedHeadSha == record.lastMergedHeadSha;
  }

  WorkspacePullRequestScope? _scopeFor(String workspaceId) {
    final workspace = _workspace(workspaceId);
    if (workspace == null) {
      return null;
    }
    return WorkspacePullRequestScope(
      workspaceId: workspace.id,
      repoPath: workspace.path,
      branch: workspace.branch,
      sourceBranch: workspace.sourceBranch,
      providerOverride: ref
          .read(effectiveHostingProviderOverrideProvider(workspace.projectId))
          .asData
          ?.value,
    );
  }

  Workspace? _workspace(String workspaceId) {
    final workbench = ref.read(workbenchControllerProvider);
    for (final workspaces in workbench.workspacesByProject.values) {
      for (final workspace in workspaces) {
        if (workspace.id == workspaceId && workspace.isActive) {
          return workspace;
        }
      }
    }
    return null;
  }
}

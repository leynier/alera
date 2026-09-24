import 'dart:async';

import 'package:alera_mobile/src/features/pull_requests/application/pull_request_watch_controller.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/agent_task_dispatch/application/agent_task_dispatch_service.dart';
import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/agent_presence_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_action_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_prompts.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pull_request_agent_watch_controller.g.dart';

final Logger _logger = Logger('PullRequestAgentWatchController');

/// Mirrors the runtime watch for the PR panel. Older hosts retain the local
/// polling fallback, kept alive across panel navigation and paused in background.
@Riverpod(keepAlive: true)
class PullRequestAgentWatchController
    extends _$PullRequestAgentWatchController {
  static const Duration pollInterval = Duration(seconds: 30);

  var _inFlight = false;
  Timer? _timer;
  bool _runtimeOwned = false;

  @override
  PullRequestAgentWatchSession? build(String hostId, String workspaceId) {
    ref.listen(pullRequestWatchControllerProvider(hostId), (_, next) {
      final snapshot = next.asData?.value;
      if (snapshot == null || !snapshot.supported) return;
      final watch = snapshot.byWorkspace[workspaceId];
      if (watch == null && !_runtimeOwned) return;
      _runtimeOwned = true;
      _timer?.cancel();
      _timer = null;
      state = watch == null
          ? null
          : PullRequestAgentWatchSession(
              hostId: hostId,
              workspaceId: workspaceId,
              reviewNumber: watch.reviewNumber,
              mode: watch.merge
                  ? PullRequestAgentWatchMode.fixAndMerge
                  : PullRequestAgentWatchMode.fix,
              binding: AgentTaskDispatchBinding(
                tabId: watch.tabId,
                profileId: watch.profileId,
                label: watch.label,
              ),
              watchScope: PullRequestAgentWatchScope(
                checks: watch.checks,
                comments: watch.comments,
                conflicts: watch.conflicts,
              ),
            );
    });
    ref.onDispose(() {
      _timer?.cancel();
      _inFlight = false;
    });
    ref.listen<AppLifecycleState>(appLifecycleControllerProvider, (
      previous,
      next,
    ) {
      _syncTimer();
      if (next == AppLifecycleState.resumed &&
          previous != AppLifecycleState.resumed &&
          state != null) {
        unawaited(_poll());
      }
    });
    final existing = ref
        .read(pullRequestWatchControllerProvider(hostId))
        .value
        ?.byWorkspace[workspaceId];
    if (existing == null) return null;
    _runtimeOwned = true;
    return PullRequestAgentWatchSession(
      hostId: hostId,
      workspaceId: workspaceId,
      reviewNumber: existing.reviewNumber,
      mode: existing.merge
          ? PullRequestAgentWatchMode.fixAndMerge
          : PullRequestAgentWatchMode.fix,
      binding: AgentTaskDispatchBinding(
        tabId: existing.tabId,
        profileId: existing.profileId,
        label: existing.label,
      ),
      watchScope: PullRequestAgentWatchScope(
        checks: existing.checks,
        comments: existing.comments,
        conflicts: existing.conflicts,
      ),
    );
  }

  Future<void> start({
    required int reviewNumber,
    required PullRequestAgentWatchMode mode,
    required AgentTaskDispatchBinding binding,
    PullRequestAgentWatchScope watchScope = PullRequestAgentWatchScope.defaults,
    PullRequestAgentWatchDispatchMark? lastDispatch,
    MobilePullRequestSnapshot? snapshot,
  }) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    if (!ref.mounted) return;
    if (client is MobilePullRequestWatchExecutionClient &&
        (client as MobilePullRequestWatchExecutionClient)
            .supportsPullRequestWatchExecution) {
      await (client as MobilePullRequestWatchExecutionClient)
          .startPullRequestWatch(<String, Object?>{
            'workspaceId': workspaceId,
            'reviewNumber': reviewNumber,
            'mode': mode.name,
            'checks': watchScope.checks,
            'comments': watchScope.comments,
            'conflicts': watchScope.conflicts,
            'tabId': binding.tabId,
            'profileId': binding.profileId,
            'label': binding.label,
          });
      if (!ref.mounted) return;
      _runtimeOwned = true;
      ref.invalidate(pullRequestWatchControllerProvider(hostId));
      await ref.read(pullRequestWatchControllerProvider(hostId).future);
      return;
    }
    _runtimeOwned = false;
    state = PullRequestAgentWatchSession(
      hostId: hostId,
      workspaceId: workspaceId,
      reviewNumber: reviewNumber,
      mode: mode,
      binding: binding,
      watchScope: watchScope,
      lastDispatch: lastDispatch,
    );
    _syncTimer();
    unawaited(_evaluate(panel: snapshot ?? _loadedPanel()));
  }

  Future<void> stop() async {
    if (_runtimeOwned) {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (client is! MobilePullRequestWatchExecutionClient ||
          !(client as MobilePullRequestWatchExecutionClient)
              .supportsPullRequestWatchExecution) {
        throw StateError('Update the runtime to stop this watch from mobile.');
      }
      await (client as MobilePullRequestWatchExecutionClient)
          .stopPullRequestWatch(workspaceId);
      if (!ref.mounted) return;
      ref.invalidate(pullRequestWatchControllerProvider(hostId));
    }
    _timer?.cancel();
    _timer = null;
    state = null;
  }

  void onSnapshot(MobilePullRequestSnapshot snapshot) {
    unawaited(_evaluate(panel: snapshot));
  }

  void _syncTimer() {
    final resumed =
        ref.read(appLifecycleControllerProvider) == AppLifecycleState.resumed;
    if (!_runtimeOwned && state != null && resumed) {
      _timer ??= Timer.periodic(pollInterval, (_) => unawaited(_poll()));
      return;
    }
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    final session = state;
    if (session == null || _runtimeOwned) {
      return;
    }
    try {
      final panel = pullRequestControllerProvider(hostId, workspaceId);
      if (ref.exists(panel)) {
        await ref.read(panel.notifier).refresh();
        await _evaluate(panel: ref.read(panel).value);
        return;
      }
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (client case final MobileWorkspacePanelsClient panels
          when panels.supportsPullRequests) {
        await _evaluate(panel: await panels.pullRequestSnapshot(workspaceId));
      }
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'could not poll pull request $workspaceId for watch',
        error,
        stackTrace,
      );
    }
  }

  MobilePullRequestSnapshot? _loadedPanel() {
    final provider = pullRequestControllerProvider(hostId, workspaceId);
    if (!ref.exists(provider)) {
      return null;
    }
    return ref.read(provider).value;
  }

  Future<void> _evaluate({MobilePullRequestSnapshot? panel}) async {
    final session = state;
    if (session == null || _runtimeOwned || _inFlight) {
      return;
    }
    _inFlight = true;
    try {
      final resolved = panel ?? _loadedPanel();
      final snapshot = resolved == null
          ? null
          : pullRequestAgentWatchSnapshotFrom(resolved);
      final evaluation = evaluatePullRequestAgentWatch(
        session: session,
        snapshot: snapshot,
      );
      switch (evaluation.action) {
        case PullRequestAgentWatchAction.none:
          return;
        case PullRequestAgentWatchAction.stop:
          await stop();
          return;
        case PullRequestAgentWatchAction.dispatch:
          await _dispatch(session, evaluation, resolved);
        case PullRequestAgentWatchAction.merge:
          await _merge(session, evaluation.headSha, resolved);
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _dispatch(
    PullRequestAgentWatchSession session,
    PullRequestAgentWatchEvaluation evaluation,
    MobilePullRequestSnapshot? panel,
  ) async {
    AgentTaskDispatchResult? result;
    String? error;
    try {
      final service = await _service();
      result = await service.dispatchBinding(
        session.binding,
        pullRequestAgentWatchPrompt(
          reviewNumber: session.reviewNumber,
          concerns: evaluation.concerns,
          baseBranch: panel?.review?.baseRefName,
        ),
      );
    } on Object catch (caught, stackTrace) {
      error = caught.toString();
      _logger.warning(
        'watch dispatch failed for $workspaceId',
        caught,
        stackTrace,
      );
    }
    final latest = state;
    if (latest == null) {
      return;
    }
    state = pullRequestAgentWatchAfterDispatch(
      session: latest,
      result: result,
      concerns: evaluation.concerns,
      headSha: evaluation.headSha,
      error: error,
    );
  }

  Future<void> _merge(
    PullRequestAgentWatchSession session,
    String? headSha,
    MobilePullRequestSnapshot? panel,
  ) async {
    final methods = panel?.mergeMethods ?? const <String>[];
    final method = preferredMobilePullRequestMergeMethod(methods);
    if (method == null) {
      final latest = state;
      if (latest != null) {
        state = latest.copyWith(
          lastError: 'Watch, Fix and Merge could not find a merge method.',
        );
      }
      return;
    }
    final error = await ref
        .read(pullRequestActionControllerProvider(hostId, workspaceId).notifier)
        .run(
          PullRequestActionKind.merge,
          (client) => client.mergePullRequest(
            workspaceId: workspaceId,
            number: session.reviewNumber,
            method: method,
          ),
        );
    final latest = state;
    if (latest == null) {
      return;
    }
    state = pullRequestAgentWatchAfterMerge(
      session: latest,
      merged: error == null,
      headSha: headSha,
      error: error,
    );
  }

  Future<AgentTaskDispatchService> _service() async {
    final terminalClient = await ref.read(
      terminalClientProvider(hostId).future,
    );
    final tabsNotifier = ref.read(
      tabsControllerProvider(hostId, workspaceId).notifier,
    );
    return AgentTaskDispatchService(
      workspaceId: workspaceId,
      terminalClient: terminalClient,
      launchProfile: (profileId, prompt) =>
          tabsNotifier.launchAgentProfileTab(profileId, prompt: prompt),
      tabs: () =>
          ref.read(tabsControllerProvider(hostId, workspaceId)).value ??
          const <WorkspaceTabSummary>[],
      runningAgents: () =>
          ref.read(agentPresenceControllerProvider(hostId)).value ??
          const <AgentPresenceSummary>[],
    );
  }
}

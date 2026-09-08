import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_providers.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pull_request_agent_watch_providers.g.dart';

@Riverpod(keepAlive: true)
class PullRequestAgentWatchController
    extends _$PullRequestAgentWatchController {
  final Set<String> _inFlight = <String>{};
  Timer? _timer;

  @override
  Map<String, PullRequestAgentWatchSession> build() {
    ref.onDispose(() {
      _timer?.cancel();
      _inFlight.clear();
    });
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
            _remove(workspaceId, detach: false);
          }
        }
      },
    );
    return const <String, PullRequestAgentWatchSession>{};
  }

  PullRequestAgentWatchSession? sessionFor(String workspaceId) =>
      state[workspaceId];

  void start({
    required WorkspacePullRequestScope scope,
    required int reviewNumber,
    required PullRequestAgentWatchMode mode,
    required AgentTaskDispatchBinding binding,
    String? lastDispatchedFailureSignature,
  }) {
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
        lastDispatchedFailureSignature: lastDispatchedFailureSignature,
      ),
    };
    _ensureTimer();
    unawaited(_evaluate(scope.workspaceId));
  }

  void stop(String workspaceId) {
    _remove(workspaceId, detach: true);
  }

  void onPanelState(String workspaceId, WorkspacePullRequestState? panel) {
    unawaited(_evaluate(workspaceId, panel: panel));
  }

  void _remove(String workspaceId, {required bool detach}) {
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
      final evaluation = evaluatePullRequestAgentWatch(
        session: session,
        snapshot: snapshot,
      );
      switch (evaluation.action) {
        case PullRequestAgentWatchAction.none:
          return;
        case PullRequestAgentWatchAction.stop:
          _remove(workspaceId, detach: true);
          return;
        case PullRequestAgentWatchAction.dispatchFix:
          await _dispatchFix(session, evaluation.failureSignature);
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
    );
  }

  Future<void> _dispatchFix(
    PullRequestAgentWatchSession session,
    String? failureSignature,
  ) async {
    final result = await completeAgentTaskDispatch(
      request: AgentTaskDispatchRequest(
        workspaceId: session.workspaceId,
        prompt: pullRequestAgentWatchPrompt(session.reviewNumber),
      ),
      binding: session.binding,
      service: readAgentTaskDispatchServiceFromRef(
        ref,
        workspaceId: session.workspaceId,
      ),
    );
    final latest = state[session.workspaceId];
    if (latest == null) {
      return;
    }
    state = <String, PullRequestAgentWatchSession>{
      ...state,
      session.workspaceId: PullRequestAgentWatchSession(
        workspaceId: latest.workspaceId,
        reviewNumber: latest.reviewNumber,
        mode: latest.mode,
        binding: result?.binding ?? latest.binding,
        scope: latest.scope,
        lastDispatchedFailureSignature:
            failureSignature ?? latest.lastDispatchedFailureSignature,
        lastMergedHeadSha: latest.lastMergedHeadSha,
      ),
    };
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
    await ref
        .read(workspacePullRequestControllerProvider(session.scope).notifier)
        .mergeReview(method);
    final latest = state[session.workspaceId];
    if (latest == null) {
      return;
    }
    state = <String, PullRequestAgentWatchSession>{
      ...state,
      session.workspaceId: PullRequestAgentWatchSession(
        workspaceId: latest.workspaceId,
        reviewNumber: latest.reviewNumber,
        mode: latest.mode,
        binding: latest.binding,
        scope: latest.scope,
        lastDispatchedFailureSignature: latest.lastDispatchedFailureSignature,
        lastMergedHeadSha: headSha ?? latest.lastMergedHeadSha,
      ),
    };
  }

  ReviewMergeMethod? _preferredMergeMethod(List<ReviewMergeMethod> methods) {
    if (methods.contains(ReviewMergeMethod.providerDefault)) {
      return ReviewMergeMethod.providerDefault;
    }
    return methods.firstOrNull;
  }
}

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_agent_watch_providers.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> dispatchPullRequestFailedChecks({
  required BuildContext context,
  required WidgetRef ref,
  required String workspaceId,
  required HostedReview review,
}) async {
  await showAgentTaskDispatchFlow(
    context,
    ref,
    request: AgentTaskDispatchRequest(
      workspaceId: workspaceId,
      prompt: pullRequestFailedChecksPrompt(review.number),
      message: 'Choose a running agent or open a new tab from a profile.',
    ),
  );
}

Future<void> startPullRequestAgentWatch({
  required BuildContext context,
  required WidgetRef ref,
  required WorkspacePullRequestScope scope,
  required HostedReview review,
  required PullRequestAgentWatchMode mode,
  required PullRequestAgentWatchScope watchScope,
  required PullRequestAgentWatchSnapshot snapshot,
}) async {
  if (watchScope.isEmpty) {
    AleraToast.show(
      context,
      message: 'Choose at least one problem to watch.',
      tone: .error,
    );
    return;
  }
  final concerns = pullRequestAgentWatchConcerns(
    snapshot: snapshot,
    scope: watchScope,
  );
  final choice = await chooseAgentTaskDispatchTarget(
    context,
    ref,
    request: AgentTaskDispatchRequest(
      workspaceId: scope.workspaceId,
      prompt: pullRequestAgentWatchPrompt(
        reviewNumber: review.number,
        concerns: concerns,
        baseBranch: review.baseBranch,
      ),
      title: mode == PullRequestAgentWatchMode.fixAndMerge
          ? 'Watch, Fix and Merge'
          : 'Watch and Fix',
      message: 'Choose a running agent or open a new tab from a profile.',
    ),
  );
  if (choice == null || !context.mounted) {
    return;
  }
  var binding = choice.binding;
  PullRequestAgentWatchDispatchMark? dispatched;
  if (pullRequestAgentWatchInjectsOnStart(concerns)) {
    final result = await completeAgentTaskDispatch(
      ref: ref,
      request: choice.request,
      selection: choice.selection,
      catalog: choice.catalog,
    );
    if (result != null) {
      binding = result.binding;
      dispatched = pullRequestAgentWatchDispatchMark(
        previous: null,
        headSha: review.headSha,
        concerns: concerns,
      );
    }
  }
  ref
      .read(pullRequestAgentWatchControllerProvider.notifier)
      .start(
        scope: scope,
        reviewNumber: review.number,
        mode: mode,
        binding: binding,
        watchScope: watchScope,
        lastDispatch: dispatched,
      );
}

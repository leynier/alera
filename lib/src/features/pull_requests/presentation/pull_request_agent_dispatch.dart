import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_ship_follow_up_runner.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_agent_watch_providers.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_follow_up.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _agentDispatchMessage =
    'Choose a running agent or open a new tab from a profile.';

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
      message: _agentDispatchMessage,
    ),
  );
}

Future<void> dispatchPullRequestRestack({
  required BuildContext context,
  required WidgetRef ref,
  required String workspaceId,
}) async {
  await showAgentTaskDispatchFlow(
    context,
    ref,
    request: AgentTaskDispatchRequest(
      workspaceId: workspaceId,
      prompt: pullRequestRestackPrompt,
      title: 'Restack Changes',
      message: _agentDispatchMessage,
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
      title: _watchTitle(mode),
      message: _agentDispatchMessage,
    ),
  );
  if (choice == null || !context.mounted) {
    return;
  }
  var binding = choice.binding;
  PullRequestAgentWatchDispatchMark? dispatched;
  final runtimeOwned =
      review.provider == GitHostingProvider.github &&
      await ref
          .read(pullRequestAgentWatchRepositoryProvider)
          .supportsExecution();
  if (!context.mounted) return;
  if (!runtimeOwned && pullRequestAgentWatchInjectsOnStart(concerns)) {
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
  try {
    await ref
        .read(pullRequestAgentWatchControllerProvider.notifier)
        .start(
          scope: scope,
          reviewNumber: review.number,
          mode: mode,
          binding: binding,
          watchScope: watchScope,
          lastDispatch: dispatched,
        );
  } on Object catch (error) {
    if (context.mounted) {
      AleraToast.show(
        context,
        message: 'Could not start watching. $error',
        tone: .error,
      );
    }
  }
}

String _watchTitle(PullRequestAgentWatchMode mode) =>
    mode == PullRequestAgentWatchMode.fixAndMerge
    ? 'Watch, Fix and Merge'
    : 'Watch and Fix';

/// Ships through [ship] and starts the watch [followUp] asks for, picking the
/// agent first. See [runPullRequestShipFollowUp].
Future<void> shipPullRequestWithFollowUp({
  required BuildContext context,
  required WidgetRef ref,
  required WorkspacePullRequestController controller,
  required PullRequestShipFollowUp followUp,
  required PullRequestAgentWatchScope watchScope,
  required Future<CreateReviewResult> Function() ship,
}) {
  final scope = controller.scope;
  // The panel can unmount while shipping; the container outlives its ref.
  final container = ProviderScope.containerOf(context, listen: false);
  final watchController = ref.read(
    pullRequestAgentWatchControllerProvider.notifier,
  );
  return runPullRequestShipFollowUp(
    followUp: followUp,
    chooseAgent: (mode) async {
      final choice = await chooseAgentTaskDispatchTarget(
        context,
        ref,
        request: AgentTaskDispatchRequest(
          workspaceId: scope.workspaceId,
          prompt:
              'Please check the pull request for this branch and fix anything '
              'that blocks it.',
          title: 'Ship, ${_watchTitle(mode)}',
          message: _agentDispatchMessage,
        ),
      );
      return choice?.binding;
    },
    ship: ship,
    reloadReviewNumber: () async {
      await controller.refresh();
      return container
          .read(workspacePullRequestControllerProvider(scope))
          .value
          ?.review
          ?.number;
    },
    startWatch: (reviewNumber, mode, binding) => watchController.start(
      scope: scope,
      reviewNumber: reviewNumber,
      mode: mode,
      binding: binding,
      watchScope: watchScope,
    ),
    onWatchFailed: (message) =>
        AleraToast.publish(message: message, tone: .error),
  );
}

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_providers.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_agent_watch_providers.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
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
  ReviewChecksRollup checksRollup = ReviewChecksRollup.none,
}) async {
  final request = AgentTaskDispatchRequest(
    workspaceId: scope.workspaceId,
    prompt: pullRequestAgentWatchPrompt(review.number),
    title: mode == PullRequestAgentWatchMode.fixAndMerge
        ? 'Watch, Fix and Merge'
        : 'Watch and Fix',
    message: 'Choose a running agent or open a new tab from a profile.',
  );
  final catalog = readAgentTaskDispatchCatalog(ref, scope.workspaceId);
  if (catalog.isEmpty) {
    AleraToast.show(
      context,
      message: 'Add an agent profile in Settings before sending work.',
      tone: .error,
    );
    return;
  }
  final selection = await showAgentTaskDispatchPicker(
    context,
    request: request,
    catalog: catalog,
  );
  if (selection == null || !context.mounted) {
    return;
  }
  final service = readAgentTaskDispatchService(
    ref,
    catalog: catalog,
    workspaceId: scope.workspaceId,
  );
  var binding = service.bindingFor(selection);
  String? dispatchedSignature;
  if (checksRollup == ReviewChecksRollup.failure) {
    final result = await completeAgentTaskDispatch(
      ref: ref,
      request: request,
      selection: selection,
      catalog: catalog,
    );
    if (result != null) {
      binding = result.binding;
      dispatchedSignature = pullRequestAgentWatchFailureSignature(
        reviewNumber: review.number,
        headSha: review.headSha,
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
        lastDispatchedFailureSignature: dispatchedSignature,
      );
}

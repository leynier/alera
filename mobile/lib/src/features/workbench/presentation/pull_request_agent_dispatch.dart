import 'package:alera_mobile/src/features/agent_task_dispatch/application/agent_task_dispatch_service.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';
import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/agent_presence_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_agent_watch_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_agent_watch_scope_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_prompts.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dispatch_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _agentDispatchMessage =
    'Choose a running agent or open a new tab from a profile.';

Future<void> dispatchPullRequestFailedChecks({
  required BuildContext context,
  required WidgetRef ref,
  required String hostId,
  required String workspaceId,
  required MobilePullRequestReview review,
}) {
  return _showAndComplete(
    context,
    ref,
    request: AgentTaskDispatchRequest(
      hostId: hostId,
      workspaceId: workspaceId,
      prompt: pullRequestFailedChecksPrompt(review.number),
      message: _agentDispatchMessage,
    ),
  );
}

Future<void> dispatchPullRequestRestack({
  required BuildContext context,
  required WidgetRef ref,
  required String hostId,
  required String workspaceId,
}) {
  return _showAndComplete(
    context,
    ref,
    request: AgentTaskDispatchRequest(
      hostId: hostId,
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
  required String hostId,
  required String workspaceId,
  required MobilePullRequestReview review,
  required PullRequestAgentWatchMode mode,
  required PullRequestAgentWatchScope watchScope,
  required MobilePullRequestSnapshot snapshot,
}) async {
  if (watchScope.isEmpty) {
    _snack(context, 'Choose at least one problem to watch.');
    return;
  }
  final concerns = pullRequestAgentWatchConcerns(
    snapshot: pullRequestAgentWatchSnapshotFrom(snapshot),
    scope: watchScope,
  );
  final choice = await chooseAgentTaskDispatchTarget(
    context,
    ref,
    request: AgentTaskDispatchRequest(
      hostId: hostId,
      workspaceId: workspaceId,
      prompt: pullRequestAgentWatchPrompt(
        reviewNumber: review.number,
        concerns: concerns,
        baseBranch: review.baseRefName,
      ),
      title: mode == PullRequestAgentWatchMode.fixAndMerge
          ? 'Watch, Fix and Merge'
          : 'Watch and Fix',
      message: _agentDispatchMessage,
    ),
  );
  if (choice == null || !context.mounted) {
    return;
  }
  var binding = choice.binding;
  PullRequestAgentWatchDispatchMark? dispatched;
  final client = await ref.read(workspaceClientProvider(hostId).future);
  final runtimeOwned =
      client is MobilePullRequestWatchExecutionClient &&
      (client as MobilePullRequestWatchExecutionClient)
          .supportsPullRequestWatchExecution;
  if (!context.mounted) return;
  if (!runtimeOwned && pullRequestAgentWatchInjectsOnStart(concerns)) {
    final result = await completeAgentTaskDispatch(
      ref: ref,
      request: choice.request,
      target: choice.target,
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
        .read(
          pullRequestAgentWatchControllerProvider(hostId, workspaceId).notifier,
        )
        .start(
          reviewNumber: review.number,
          mode: mode,
          binding: binding,
          watchScope: watchScope,
          lastDispatch: dispatched,
          snapshot: snapshot,
        );
  } on Object catch (error) {
    if (context.mounted) _snack(context, 'Could not start watching. $error');
  }
}

class const AgentTaskDispatchChoice({
  required final AgentTaskDispatchRequest request,
  required final WorkspaceAgentCommentTarget target,
  required final AgentTaskDispatchBinding binding,
});

Future<AgentTaskDispatchChoice?> chooseAgentTaskDispatchTarget(
  BuildContext context,
  WidgetRef ref, {
  required AgentTaskDispatchRequest request,
}) async {
  final prompt = request.prompt.trim();
  if (prompt.isEmpty) {
    _snack(context, 'The prompt is empty.');
    return null;
  }
  final normalized = AgentTaskDispatchRequest(
    hostId: request.hostId,
    workspaceId: request.workspaceId,
    prompt: prompt,
    title: request.title,
    message: request.message,
  );
  final (runningAgents, profiles) = await (
    _runningAgents(ref, normalized.hostId, normalized.workspaceId),
    _allProfiles(ref, normalized.hostId),
  ).wait;
  if (!context.mounted) {
    return null;
  }
  if (runningAgents.isEmpty && profiles.isEmpty) {
    _snack(context, 'Add an agent profile in Settings before sending work.');
    return null;
  }
  final target = await showWorkspaceAgentCommentDispatchSheet(
    context,
    runningAgents: runningAgents,
    profiles: profiles,
    title: normalized.title,
    message: normalized.message,
  );
  if (target == null || !context.mounted) {
    return null;
  }
  return AgentTaskDispatchChoice(
    request: normalized,
    target: target,
    binding: agentTaskDispatchBindingFor(target),
  );
}

Future<void> _showAndComplete(
  BuildContext context,
  WidgetRef ref, {
  required AgentTaskDispatchRequest request,
}) async {
  final choice = await chooseAgentTaskDispatchTarget(
    context,
    ref,
    request: request,
  );
  if (choice == null || !context.mounted) {
    return;
  }
  await completeAgentTaskDispatch(
    ref: ref,
    request: choice.request,
    target: choice.target,
    messenger: ScaffoldMessenger.of(context),
  );
}

Future<AgentTaskDispatchResult?> completeAgentTaskDispatch({
  required WidgetRef ref,
  required AgentTaskDispatchRequest request,
  WorkspaceAgentCommentTarget? target,
  AgentTaskDispatchBinding? binding,
  ScaffoldMessengerState? messenger,
}) async {
  try {
    final service = await _serviceFor(ref, request);
    final result = target != null
        ? await service.dispatchTarget(target, request.prompt)
        : await service.dispatchBinding(
            binding ?? const AgentTaskDispatchBinding(),
            request.prompt,
          );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.openedNewTab
              ? 'Opened ${result.label}'
              : 'Sent to ${result.label}',
        ),
      ),
    );
    return result;
  } on AgentTaskDispatchException catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    return null;
  } on Object catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(error.toString())));
    return null;
  }
}

Future<void> persistPullRequestAgentWatchScope(
  WidgetRef ref,
  PullRequestAgentWatchScope scope,
) {
  return ref
      .read(pullRequestAgentWatchScopeControllerProvider.notifier)
      .set(scope);
}

Future<AgentTaskDispatchService> _serviceFor(
  WidgetRef ref,
  AgentTaskDispatchRequest request,
) async {
  final terminalClient = await ref.read(
    terminalClientProvider(request.hostId).future,
  );
  final tabs =
      ref
          .read(tabsControllerProvider(request.hostId, request.workspaceId))
          .value ??
      const <WorkspaceTabSummary>[];
  final presence =
      ref.read(agentPresenceControllerProvider(request.hostId)).value ??
      const <AgentPresenceSummary>[];
  final tabsNotifier = ref.read(
    tabsControllerProvider(request.hostId, request.workspaceId).notifier,
  );
  return AgentTaskDispatchService(
    workspaceId: request.workspaceId,
    terminalClient: terminalClient,
    launchProfile: (profileId, prompt) =>
        tabsNotifier.launchAgentProfileTab(profileId, prompt: prompt),
    tabs: () =>
        ref
            .read(tabsControllerProvider(request.hostId, request.workspaceId))
            .value ??
        tabs,
    runningAgents: () =>
        ref.read(agentPresenceControllerProvider(request.hostId)).value ??
        presence,
  );
}

Future<List<AgentPresenceSummary>> _runningAgents(
  WidgetRef ref,
  String hostId,
  String workspaceId,
) async {
  final presence = await ref.read(
    agentPresenceControllerProvider(hostId).future,
  );
  return <AgentPresenceSummary>[
    for (final agent in presence)
      if (agent.workspaceId == workspaceId) agent,
  ];
}

Future<List<AgentProfileSummary>> _allProfiles(
  WidgetRef ref,
  String hostId,
) async {
  final client = await ref.read(workspaceClientProvider(hostId).future);
  return client.listAgentProfiles();
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

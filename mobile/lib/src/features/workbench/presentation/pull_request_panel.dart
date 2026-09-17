import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_refresh_progress.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_action_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_agent_watch_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_agent_watch_scope_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_action_bar.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_agent_actions.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_agent_dispatch.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_checks_section.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_conversation_section.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_panel_actions.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_panel_header.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_restack_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const PullRequestPanel({
  super.key,
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pullRequestControllerProvider(hostId, workspaceId);
    final state = ref.watch(provider);
    final supportsActions =
        ref.watch(pullRequestActionsSupportedProvider(hostId)).value ?? false;
    final canGenerate =
        ref
            .watch(pullRequestDetailsGenerationSupportedProvider(hostId))
            .value ??
        false;
    final canShip =
        ref.watch(pullRequestShipSupportedProvider(hostId)).value ?? false;
    // Default to offering removal until the list answers; hiding it after a
    // merged review would promote Unlink into the primary button for a frame.
    final offerRemoveWorkspace =
        ref
            .watch(workspaceListControllerProvider(hostId))
            .value
            ?.supportsMutations ??
        true;
    final busy = ref.watch(
      pullRequestActionControllerProvider(hostId, workspaceId),
    );
    final watchSession = ref.watch(
      pullRequestAgentWatchControllerProvider(hostId, workspaceId),
    );
    final watchScope =
        ref.watch(pullRequestAgentWatchScopeControllerProvider).value ??
        PullRequestAgentWatchScope.defaults;
    ref.listen(provider, (previous, next) {
      final snapshot = next.value;
      if (snapshot != null) {
        ref
            .read(
              pullRequestAgentWatchControllerProvider(
                hostId,
                workspaceId,
              ).notifier,
            )
            .onSnapshot(snapshot);
      }
    });
    final actions = supportsActions
        ? PullRequestPanelActions(
            ref: ref,
            hostId: hostId,
            workspaceId: workspaceId,
          )
        : null;
    final messenger = ScaffoldMessenger.of(context);
    Future<void> refresh() async {
      final error = await ref.read(provider.notifier).refresh();
      if (error != null && messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      }
    }

    void reload() => unawaited(ref.read(provider.notifier).reload());
    // The last snapshot wins over a reload, so a host reconnect does not blank
    // the review into a spinner; see `SourceControlPanel`.
    final snapshot = state.value;
    if (snapshot == null) {
      return switch (state) {
        AsyncError(:final error) => AleraEmptyState(
          icon: AleraIcons.gitPullRequest,
          message: error.toString(),
          action: FilledButton(onPressed: reload, child: const Text('Retry')),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Column(
      children: <Widget>[
        AleraRefreshProgress(refreshing: state.isLoading),
        if (state.error case final error?)
          Padding(
            padding: AleraTokens.contentPadding,
            child: AleraNotice(
              icon: AleraIcons.warning,
              message: 'Could not refresh the pull request. $error',
              action: TextButton(onPressed: reload, child: const Text('Retry')),
            ),
          ),
        Expanded(
          child: _Body(
            hostId: hostId,
            workspaceId: workspaceId,
            snapshot: snapshot,
            actions: actions,
            busy: busy,
            watchSession: watchSession,
            watchScope: watchScope,
            onRefresh: refresh,
            onReload: reload,
            canGenerate: canGenerate && snapshot.aiAssistEnabled,
            canShip: canShip && snapshot.aiAssistEnabled,
            offerRemoveWorkspace: offerRemoveWorkspace,
          ),
        ),
      ],
    );
  }
}

class const _Body({
  required final String hostId,
  required final String workspaceId,
  required final MobilePullRequestSnapshot snapshot,
  required final PullRequestPanelActions? actions,
  required final PullRequestActionKind? busy,
  required final PullRequestAgentWatchSession? watchSession,
  required final PullRequestAgentWatchScope watchScope,
  required final Future<void> Function() onRefresh,
  required final VoidCallback onReload,
  required final bool canGenerate,
  required final bool canShip,
  required final bool offerRemoveWorkspace,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = snapshot.review;
    final actions = this.actions;
    if (review == null) {
      return PullRequestPanelEmptyState(
        hostId: hostId,
        workspaceId: workspaceId,
        snapshot: snapshot,
        actions: actions,
        busy: busy,
        onRefresh: onRefresh,
        canGenerate: canGenerate,
        canShip: canShip,
      );
    }
    final theme = Theme.of(context);
    final idle = busy == null;
    final watching = watchSession != null;
    final checksFailed = pullRequestChecksFailed(review.checks);
    return RefreshIndicator(
      onRefresh: onRefresh,
      // Pull-to-refresh stays disabled while a write runs, like the header
      // button, so its snapshot cannot race the write's answer.
      notificationPredicate: (notification) => idle && notification.depth == 0,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space16,
          AleraTokens.space16,
          AleraTokens.space24,
        ),
        children: <Widget>[
          PullRequestPanelHeader(
            snapshot: snapshot,
            review: review,
            onRefresh: idle ? () => unawaited(onRefresh()) : null,
            watchButton: PullRequestWatchHeaderButton(
              reviewIsOpen: review.isOpen,
              busy: !idle,
              watchMode: watchSession?.mode,
              watchScope: watchScope,
              canFixAndMerge: actions != null,
              onWatchScopeChanged: (scope) =>
                  unawaited(persistPullRequestAgentWatchScope(ref, scope)),
              onWatchStarted: (result) => unawaited(
                startPullRequestAgentWatch(
                  context: context,
                  ref: ref,
                  hostId: hostId,
                  workspaceId: workspaceId,
                  review: review,
                  mode: result.mode,
                  watchScope: result.scope,
                  snapshot: snapshot,
                ),
              ),
              onStopAgentWatch: watching
                  ? () async {
                      try {
                        await ref
                            .read(
                              pullRequestAgentWatchControllerProvider(
                                hostId,
                                workspaceId,
                              ).notifier,
                            )
                            .stop();
                      } on Object catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not stop watching. $error'),
                            ),
                          );
                        }
                      }
                    }
                  : null,
            ),
          ),
          if (watchSession != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            PullRequestWatchStatus(mode: watchSession!.mode),
            if (watchSession!.lastError case final error?) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              AleraNotice(icon: AleraIcons.warning, message: error),
            ],
          ],
          const SizedBox(height: AleraTokens.space12),
          if (review.isOpen) ...<Widget>[
            PullRequestRestackButton(
              enabled: idle,
              onPressed: () => unawaited(
                dispatchPullRequestRestack(
                  context: context,
                  ref: ref,
                  hostId: hostId,
                  workspaceId: workspaceId,
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
          ],
          if (actions == null)
            const AleraNotice(
              icon: AleraIcons.info,
              message: 'Comments are read-only. Update the paired Alera runtime to reply, edit, and merge from the phone.',
            )
          else ...<Widget>[
            PullRequestActionBar(
              actions: availablePullRequestReviewActions(
                snapshot,
                offerRemoveWorkspace: offerRemoveWorkspace,
              ),
              isEnabled: (action) =>
                  pullRequestReviewActionEnabled(action, review),
              busy: !idle,
              onSelected: (action) =>
                  unawaited(actions.runReviewAction(context, snapshot, action)),
            ),
            if (snapshot.mergeMethodsError case final error?) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              AleraNotice(
                icon: AleraIcons.info,
                message: 'Merge methods are unavailable: $error',
              ),
            ],
          ],
          const SizedBox(height: AleraTokens.space16),
          AleraSectionHeader(
            label: 'Checks',
            padding: const EdgeInsets.only(bottom: AleraTokens.space8),
            trailing: Wrap(
              alignment: .end,
              crossAxisAlignment: .center,
              children: <Widget>[
                if (review.checks.isNotEmpty)
                  Text(
                    pullRequestChecksSummary(review.checks),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                PullRequestFixFailedChecksButton(
                  visible: review.isOpen && idle && !watching && checksFailed,
                  onPressed: () => unawaited(
                    dispatchPullRequestFailedChecks(
                      context: context,
                      ref: ref,
                      hostId: hostId,
                      workspaceId: workspaceId,
                      review: review,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (review.checks.isEmpty)
            Text(
              'No checks were returned for this pull request.',
              style: theme.textTheme.bodySmall,
            )
          else
            PullRequestChecksSection(checks: review.checks),
          const SizedBox(height: AleraTokens.space16),
          PullRequestConversationSection(
            comments: review.comments,
            onAddComment: actions != null && snapshot.canComment && idle
                ? () => unawaited(actions.addComment(context, review.number))
                : null,
            onReply: actions != null && snapshot.canComment && idle
                ? (thread) =>
                      unawaited(actions.reply(context, review.number, thread))
                : null,
            onEdit: actions != null && idle
                ? (comment) =>
                      unawaited(actions.edit(context, review.number, comment))
                : null,
          ),
        ],
      ),
    );
  }
}

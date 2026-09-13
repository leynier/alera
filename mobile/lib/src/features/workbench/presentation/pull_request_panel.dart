import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_action_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_action_bar.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_checks_section.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_conversation_section.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_panel_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final busy = ref.watch(
      pullRequestActionControllerProvider(hostId, workspaceId),
    );
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

    // A loaded snapshot outranks a later failure: a refresh that could not
    // reach the runtime reports itself in a snack bar instead of blanking the
    // panel back to its first-load state.
    return switch (state) {
      AsyncValue(value: final snapshot?) => _Body(
        snapshot: snapshot,
        actions: actions,
        busy: busy,
        onRefresh: refresh,
        canGenerate: canGenerate && snapshot.aiAssistEnabled,
        canShip: canShip && snapshot.aiAssistEnabled,
      ),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.gitPullRequest,
        message: error.toString(),
        action: FilledButton(
          onPressed: () => ref.read(provider.notifier).reload(),
          child: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class const _Body({
  required final MobilePullRequestSnapshot snapshot,
  required final PullRequestPanelActions? actions,
  required final PullRequestActionKind? busy,
  required final Future<void> Function() onRefresh,
  required final bool canGenerate,
  required final bool canShip,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final review = snapshot.review;
    final actions = this.actions;
    if (review == null) {
      return _NoReview(
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
          _Header(
            snapshot: snapshot,
            review: review,
            onRefresh: idle ? () => unawaited(onRefresh()) : null,
          ),
          const SizedBox(height: AleraTokens.space12),
          if (actions == null)
            const AleraNotice(
              icon: AleraIcons.info,
              message: 'Comments are read-only. Update the paired Alera runtime to reply, edit, and merge from the phone.',
            )
          else ...<Widget>[
            PullRequestActionBar(
              actions: availablePullRequestReviewActions(snapshot),
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
            trailing: review.checks.isEmpty
                ? null
                : Text(
                    pullRequestChecksSummary(review.checks),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
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

/// No review to show: say why, and on a runtime that can write, offer to link
/// one or create one for the workspace branch.
class const _NoReview({
  required final MobilePullRequestSnapshot snapshot,
  required final PullRequestPanelActions? actions,
  required final PullRequestActionKind? busy,
  required final Future<void> Function() onRefresh,
  required final bool canGenerate,
  required final bool canShip,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    final canWrite =
        actions != null &&
        snapshot.provider == 'github' &&
        snapshot.authStatus == 'authenticated';
    final idle = busy == null;
    final suggested = snapshot.suggestedReview;
    return AleraEmptyState(
      icon: AleraIcons.gitPullRequest,
      title: snapshot.identity?.label ?? snapshot.branch ?? 'Pull Request',
      message:
          snapshot.unavailableReason ??
          'No pull request is available for this workspace.',
      action: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (canWrite) ...<Widget>[
            if (canShip)
              FilledButton.icon(
                onPressed: idle
                    ? () => unawaited(actions.ship(context, snapshot))
                    : null,
                icon: const Icon(AleraIcons.gitPullRequest),
                label: const Text('Ship Changes'),
              ),
            if (suggested != null)
              FilledButton.icon(
                onPressed: idle
                    ? () => unawaited(
                        actions.link(
                          context,
                          reference: '#${suggested.number}',
                        ),
                      )
                    : null,
                icon: const Icon(AleraIcons.link),
                label: Text('Link #${suggested.number}'),
              ),
            OutlinedButton.icon(
              onPressed: idle ? () => unawaited(actions.link(context)) : null,
              icon: const Icon(AleraIcons.link),
              label: const Text('Link Pull Request'),
            ),
            OutlinedButton.icon(
              onPressed: idle
                  ? () => unawaited(
                      actions.create(
                        context,
                        snapshot,
                        canGenerate: canGenerate,
                      ),
                    )
                  : null,
              icon: const Icon(AleraIcons.gitPullRequest),
              label: const Text('Create Pull Request'),
            ),
          ],
          TextButton.icon(
            onPressed: idle ? () => unawaited(onRefresh()) : null,
            icon: const Icon(AleraIcons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class const _Header({
  required final MobilePullRequestSnapshot snapshot,
  required final MobilePullRequestReview review,
  required final VoidCallback? onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = snapshot.identity?.label;
    final stateLabel = _reviewStateLabel(review);
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        if (identity != null)
          Text(
            identity,
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        Row(
          crossAxisAlignment: .center,
          children: <Widget>[
            Expanded(
              child: Text(review.title, style: theme.textTheme.titleLarge),
            ),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: AleraIcons.refresh,
              onPressed: onRefresh,
            ),
            if (review.url.isNotEmpty)
              AleraIconButton(
                tooltip: 'Open In Browser',
                icon: AleraIcons.external,
                onPressed: () => _openUrl(review.url),
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space8),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            AleraBadge(
              label: stateLabel,
              color: _reviewStateColor(stateLabel).withValues(alpha: 0.16),
              foregroundColor: _reviewStateColor(stateLabel),
            ),
            Text('#${review.number}', style: theme.textTheme.bodySmall),
            if (review.author != null)
              Text(review.author!, style: theme.textTheme.bodySmall),
          ],
        ),
        if (review.baseRefName != null &&
            review.headRefName != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.gitBranch,
                size: 14,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  review.headRefName!,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                ),
                child: Text('into', style: theme.textTheme.bodySmall),
              ),
              Flexible(
                child: Text(
                  review.baseRefName!,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoStyle,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _reviewStateLabel(MobilePullRequestReview review) {
  if (review.isDraft) {
    return 'Draft';
  }
  return switch (review.state.toUpperCase()) {
    'MERGED' => 'Merged',
    'CLOSED' => 'Closed',
    'OPEN' => 'Open',
    _ => _titleCase(review.state),
  };
}

Color _reviewStateColor(String label) {
  return switch (label) {
    'Open' => AleraTokens.success,
    'Merged' => AleraTokens.info,
    'Draft' => AleraTokens.warning,
    'Closed' => AleraTokens.foregroundMuted,
    _ => AleraTokens.foregroundMuted,
  };
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  final lower = value.toLowerCase().replaceAll('_', ' ');
  return lower[0].toUpperCase() + lower.substring(1);
}

void _openUrl(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) {
    return;
  }
  unawaited(launchUrl(parsed, mode: .externalApplication));
}

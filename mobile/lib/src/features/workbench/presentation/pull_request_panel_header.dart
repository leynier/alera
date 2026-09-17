import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_agent_dispatch.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_panel_actions.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_restack_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Empty Pull Request panel: why nothing is linked, plus Restack, Ship, link,
/// and create when the runtime can write.
class const PullRequestPanelEmptyState({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final MobilePullRequestSnapshot snapshot,
  required final PullRequestPanelActions? actions,
  required final PullRequestActionKind? busy,
  required final Future<void> Function() onRefresh,
  required final bool canGenerate,
  required final bool canShip,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class const PullRequestPanelHeader({
  super.key,
  required final MobilePullRequestSnapshot snapshot,
  required final MobilePullRequestReview review,
  required final VoidCallback? onRefresh,
  required final Widget watchButton,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = snapshot.identity?.label;
    final stateLabel = pullRequestReviewStateLabel(review);
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
            watchButton,
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
              color: pullRequestReviewStateColor(stateLabel)
                  .withValues(alpha: 0.16),
              foregroundColor: pullRequestReviewStateColor(stateLabel),
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

String pullRequestReviewStateLabel(MobilePullRequestReview review) {
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

Color pullRequestReviewStateColor(String label) {
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

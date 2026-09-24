import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/comment_relative_time.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_conversation.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_comment_markdown.dart';
import 'package:flutter/material.dart';

/// Task-list editing shared by every comment body in the conversation.
class const PullRequestCommentTasks({
  required final bool editable,
  required final Set<String> savingCommentIds,
  required final Future<void> Function(String commentId, int itemIndex)
  onToggle,
});

/// A top-level conversation comment or review summary: author, relative
/// time, and a Markdown body set on a rail so consecutive comments read as a
/// timeline instead of a stack of cards.
class const PullRequestConversationComment({
  super.key,
  required final ReviewComment comment,
  required final DateTime now,
  required final PullRequestCommentTasks tasks,
  required final Future<void> Function(String url) onOpenUrl,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isReviewSummary =
        comment.locator?.source == ReviewCommentSource.reviewSummary;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        PullRequestCommentMeta(
          comment: comment,
          now: now,
          tag: isReviewSummary ? 'Review' : null,
          onOpenUrl: onOpenUrl,
        ),
        const SizedBox(height: AleraTokens.space4),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AleraTokens.borderSubtle,
                width: AleraTokens.space2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space12),
            child: _CommentBody(
              comment: comment,
              tasks: tasks,
              onOpenUrl: onOpenUrl,
            ),
          ),
        ),
      ],
    );
  }
}

/// Review comments on one diff location. A resolved thread collapses to its
/// header; [onToggle] is null for threads that cannot collapse.
class const PullRequestConversationThread({
  super.key,
  required final ReviewConversationThread thread,
  required final DateTime now,
  required final bool expanded,
  final VoidCallback? onToggle,
  required final PullRequestCommentTasks tasks,
  required final Future<void> Function(String url) onOpenUrl,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = thread.comments.length;
    final radius = BorderRadius.circular(AleraTokens.radiusMd);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  if (onToggle != null) ...<Widget>[
                    Icon(
                      expanded
                          ? AleraIcons.chevronDown
                          : AleraIcons.chevronRight,
                      size: AleraTokens.iconMd,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space4),
                  ],
                  const Icon(
                    AleraIcons.code,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundFaint,
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Expanded(
                    child: Text(
                      thread.location ?? 'Review comment',
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: AleraTokens.monoStyle.copyWith(
                        color: AleraTokens.foregroundMuted,
                        fontSize: theme.textTheme.labelSmall?.fontSize,
                      ),
                    ),
                  ),
                  if (!expanded) ...<Widget>[
                    const SizedBox(width: AleraTokens.space6),
                    Text(
                      count == 1 ? '1 comment' : '$count comments',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                  ],
                  if (thread.resolved) ...<Widget>[
                    const SizedBox(width: AleraTokens.space6),
                    AleraBadge(
                      label: 'Resolved',
                      color: AleraTokens.success.withValues(alpha: 0.15),
                      foregroundColor: AleraTokens.success,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded)
            for (final comment in thread.comments) ...<Widget>[
              const Divider(
                height: AleraTokens.dividerExtent,
                thickness: AleraTokens.dividerExtent,
                color: AleraTokens.borderSubtle,
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    PullRequestCommentMeta(
                      comment: comment,
                      now: now,
                      onOpenUrl: onOpenUrl,
                    ),
                    const SizedBox(height: AleraTokens.space6),
                    _CommentBody(
                      comment: comment,
                      tasks: tasks,
                      onOpenUrl: onOpenUrl,
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

/// Author, relative time (absolute on hover), an optional tag, and the link
/// to the comment on the forge.
class const PullRequestCommentMeta({
  super.key,
  required final ReviewComment comment,
  required final DateTime now,
  final String? tag,
  required final Future<void> Function(String url) onOpenUrl,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final local = comment.createdAt.toLocal();
    final date = local.year == now.toLocal().year
        ? localizations.formatShortMonthDay(local)
        : localizations.formatShortDate(local);
    final fullDate = localizations.formatFullDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    final url = comment.url;
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  comment.author,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: .w600,
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space6),
              Tooltip(
                message: '$fullDate · $time',
                child: Text(
                  commentRelativeTimeLabel(comment.createdAt, now) ?? date,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ),
              if (tag != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                AleraBadge(label: tag!),
              ],
            ],
          ),
        ),
        if (url != null)
          AleraIconButton(
            tooltip: 'Open Comment',
            icon: AleraIcons.external,
            onPressed: () => onOpenUrl(url),
          ),
      ],
    );
  }
}

class const _CommentBody({
  required final ReviewComment comment,
  required final PullRequestCommentTasks tasks,
  required final Future<void> Function(String url) onOpenUrl,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PullRequestCommentMarkdown(
      body: comment.body,
      onOpenUrl: onOpenUrl,
      taskListEditable: tasks.editable && comment.locator != null,
      taskListSaving: tasks.savingCommentIds.contains(comment.id),
      onTaskListItemToggle: (itemIndex) =>
          tasks.onToggle(comment.id, itemIndex),
    );
  }
}

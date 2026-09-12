import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/design_system/markdown/alera_markdown_view.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/updater/infra/mobile_external_browser.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_pull_request_conversation.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_markdown_uri_policy.dart';
import 'package:flutter/material.dart';

/// Read-only pull-request conversation for a phone: conversation comments and
/// review summaries as a timeline, diff comments grouped into threads with
/// resolved ones collapsed. [now] pins relative times for tests; [openUrl]
/// opens forge links and defaults to the standalone browser.
class const PullRequestConversationSection({
  super.key,
  required final List<MobilePullRequestComment> comments,
  final DateTime? now,
  final Future<bool> Function(Uri url) openUrl = openMobileExternalBrowser,
}) extends StatefulWidget {
  @override
  State<PullRequestConversationSection> createState() =>
      _PullRequestConversationSectionState();
}

class _PullRequestConversationSectionState
    extends State<PullRequestConversationSection> {
  late MobilePullRequestConversation _conversation =
      buildMobilePullRequestConversation(widget.comments);
  final Set<String> _expandedResolvedThreads = <String>{};

  @override
  void didUpdateWidget(PullRequestConversationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.comments, widget.comments)) {
      return;
    }
    _conversation = buildMobilePullRequestConversation(widget.comments);
    _expandedResolvedThreads.retainAll(<String>{
      for (final entry in _conversation.entries)
        if (entry is MobilePullRequestConversationThread) entry.id,
    });
  }

  void _toggleThread(String id) {
    setState(() {
      if (!_expandedResolvedThreads.remove(id)) {
        _expandedResolvedThreads.add(id);
      }
    });
  }

  void _open(String url) {
    final uri = Uri.tryParse(url);
    if (isSupportedMarkdownViewerLinkUri(uri)) {
      unawaited(widget.openUrl(uri!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversation = _conversation;
    final now = widget.now ?? DateTime.now();
    final unresolved = conversation.unresolvedThreadCount;
    final faint = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundFaint,
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraSectionHeader(
          label: 'Comments',
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          trailing: conversation.isEmpty
              ? null
              : Row(
                  mainAxisSize: .min,
                  children: <Widget>[
                    if (unresolved > 0) ...<Widget>[
                      Text(
                        '$unresolved unresolved',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AleraTokens.warning,
                        ),
                      ),
                      Text(' · ', style: faint),
                    ],
                    Text('${conversation.commentCount}', style: faint),
                  ],
                ),
        ),
        if (conversation.isEmpty)
          Text('No comments yet.', style: theme.textTheme.bodySmall)
        else
          for (final (index, entry)
              in conversation.entries.indexed) ...<Widget>[
            if (index > 0) const SizedBox(height: AleraTokens.space16),
            switch (entry) {
              MobilePullRequestConversationComment(:final comment) =>
                _ConversationComment(comment: comment, now: now, onOpen: _open),
              MobilePullRequestConversationThread() => _ConversationThread(
                thread: entry,
                now: now,
                expanded:
                    !entry.resolved ||
                    _expandedResolvedThreads.contains(entry.id),
                onToggle: entry.resolved ? () => _toggleThread(entry.id) : null,
                onOpen: _open,
              ),
            },
          ],
      ],
    );
  }
}

class const _ConversationComment({
  required final MobilePullRequestComment comment,
  required final DateTime now,
  required final ValueChanged<String> onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _CommentMeta(
          comment: comment,
          now: now,
          tag: comment.isReviewSummary ? 'Review' : null,
          onOpen: onOpen,
        ),
        const SizedBox(height: AleraTokens.space4),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AleraTokens.borderSubtle,
                width: AleraTokens.strokeSm,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space12),
            child: _CommentBody(body: comment.body, onOpen: onOpen),
          ),
        ),
      ],
    );
  }
}

class const _ConversationThread({
  required final MobilePullRequestConversationThread thread,
  required final DateTime now,
  required final bool expanded,
  final VoidCallback? onToggle,
  required final ValueChanged<String> onOpen,
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AleraTokens.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                ),
                child: Row(
                  children: <Widget>[
                    if (onToggle != null) ...<Widget>[
                      Icon(
                        expanded
                            ? AleraIcons.chevronDown
                            : AleraIcons.chevronRight,
                        size: AleraTokens.iconSm,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.space6),
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
                        color: AleraTokens.success.withValues(alpha: 0.16),
                        foregroundColor: AleraTokens.success,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            for (final comment in thread.comments) ...<Widget>[
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    _CommentMeta(comment: comment, now: now, onOpen: onOpen),
                    const SizedBox(height: AleraTokens.space6),
                    _CommentBody(body: comment.body, onOpen: onOpen),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class const _CommentMeta({
  required final MobilePullRequestComment comment,
  required final DateTime now,
  final String? tag,
  required final ValueChanged<String> onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = _timeLabel(context);
    final url = comment.url;
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  comment.author ?? 'Unknown author',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: .w600,
                  ),
                ),
              ),
              if (time != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                Text(
                  time,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
              if (tag != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                AleraBadge(label: tag!),
              ],
            ],
          ),
        ),
        if (url != null && url.isNotEmpty)
          AleraIconButton(
            tooltip: 'Open Comment',
            icon: AleraIcons.external,
            onPressed: () => onOpen(url),
          ),
      ],
    );
  }

  String? _timeLabel(BuildContext context) {
    final created = comment.createdAtTime;
    if (created == null) {
      return null;
    }
    final relative = pullRequestCommentRelativeTimeLabel(created, now);
    if (relative != null) {
      return relative;
    }
    final localizations = MaterialLocalizations.of(context);
    final local = created.toLocal();
    return local.year == now.toLocal().year
        ? localizations.formatShortMonthDay(local)
        : localizations.formatShortDate(local);
  }
}

class const _CommentBody({
  required final String body,
  required final ValueChanged<String> onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraMarkdownView(
      data: body,
      onLinkTap: onOpen,
      imageBuilder: _commentImage,
    );
  }
}

Widget _commentImage(
  BuildContext context,
  String imageUrl,
  double? width,
  double? height,
) {
  if (!isSupportedMarkdownViewerRemoteImageUri(Uri.tryParse(imageUrl))) {
    return const _CommentImagePlaceholder();
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    child: Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: .contain,
      errorBuilder: (_, _, _) => const _CommentImagePlaceholder(),
    ),
  );
}

class const _CommentImagePlaceholder() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: AleraTokens.space48,
      height: AleraTokens.space48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: const Icon(
        AleraIcons.imageError,
        color: AleraTokens.foregroundMuted,
      ),
    );
  }
}

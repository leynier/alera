import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_conversation.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_comment_composer.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_conversation_entries.dart';
import 'package:flutter/material.dart';

/// Presentational pull-request conversation: conversation comments and review
/// summaries as a timeline, diff comments grouped into threads (resolved ones
/// collapsed), and a composer at the end when [canComment]. Pure: data and
/// callbacks in via parameters, no Riverpod reads. [now] pins relative times
/// for previews and tests.
class const PullRequestConversation({
  super.key,
  required final List<ReviewComment> comments,
  required final bool canComment,
  final bool canEditComments = false,
  final Set<String> savingCommentIds = const <String>{},
  final bool busy = false,
  final bool posting = false,
  required final Future<bool> Function(String body) onAddComment,
  required final Future<void> Function(String commentId, int itemIndex)
  onToggleTask,
  required final Future<void> Function(String url) onOpenUrl,
  final DateTime? now,
}) extends StatefulWidget {
  @override
  State<PullRequestConversation> createState() =>
      _PullRequestConversationState();
}

class _PullRequestConversationState extends State<PullRequestConversation> {
  late ReviewConversation _conversation = buildReviewConversation(
    widget.comments,
  );
  final Set<String> _expandedResolvedThreads = <String>{};

  @override
  void didUpdateWidget(PullRequestConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.comments, widget.comments)) {
      return;
    }
    _conversation = buildReviewConversation(widget.comments);
    _expandedResolvedThreads.retainAll(<String>{
      for (final entry in _conversation.entries)
        if (entry is ReviewConversationThread) entry.id,
    });
  }

  void _toggleThread(String id) {
    setState(() {
      if (!_expandedResolvedThreads.remove(id)) {
        _expandedResolvedThreads.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversation = _conversation;
    final now = widget.now ?? DateTime.now();
    final unresolved = conversation.unresolvedThreadCount;
    final tasks = PullRequestCommentTasks(
      editable: widget.canEditComments,
      savingCommentIds: widget.savingCommentIds,
      onToggle: widget.onToggleTask,
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              conversation.isEmpty
                  ? 'Comments'
                  : 'Comments (${conversation.commentCount})',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (unresolved > 0) ...<Widget>[
              const SizedBox(width: AleraTokens.space8),
              Text(
                '$unresolved unresolved',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.warning,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AleraTokens.space8),
        if (conversation.isEmpty)
          Text(
            'No comments yet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          )
        else
          for (final (index, entry)
              in conversation.entries.indexed) ...<Widget>[
            if (index > 0) const SizedBox(height: AleraTokens.space16),
            switch (entry) {
              ReviewConversationComment(:final comment) =>
                PullRequestConversationComment(
                  comment: comment,
                  now: now,
                  tasks: tasks,
                  onOpenUrl: widget.onOpenUrl,
                ),
              ReviewConversationThread() => PullRequestConversationThread(
                thread: entry,
                now: now,
                expanded:
                    !entry.resolved ||
                    _expandedResolvedThreads.contains(entry.id),
                onToggle: entry.resolved ? () => _toggleThread(entry.id) : null,
                tasks: tasks,
                onOpenUrl: widget.onOpenUrl,
              ),
            },
          ],
        if (widget.canComment) ...<Widget>[
          const SizedBox(height: AleraTokens.space16),
          PullRequestCommentComposer(
            hintText: conversation.isEmpty
                ? 'Start the conversation'
                : 'Add a comment',
            busy: widget.busy,
            posting: widget.posting,
            onSubmit: widget.onAddComment,
          ),
        ],
      ],
    );
  }
}

part of 'pull_request_review_view.dart';

class const _PullRequestCommentsSection({
  required final List<ReviewComment> comments,
  required final bool canComment,
  required final bool canEditComments,
  required final Set<String> savingCommentIds,
  required final PullRequestAction? action,
  required final Future<bool> Function(String body) onAddComment,
  required final Future<void> Function(String commentId, int itemIndex)
  onToggleTask,
  required final Future<void> Function(String url) onOpenUrl,
}) extends StatefulWidget {
  @override
  State<_PullRequestCommentsSection> createState() =>
      _PullRequestCommentsSectionState();
}

class _PullRequestCommentsSectionState
    extends State<_PullRequestCommentsSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _composing = false;

  bool get _busy => widget.action != null;
  bool get _posting => widget.action == PullRequestAction.comment;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startComment() {
    setState(() => _composing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _postComment() async {
    final posted = await widget.onAddComment(_controller.text);
    if (posted && mounted) {
      _controller.clear();
      setState(() => _composing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              widget.comments.isEmpty
                  ? 'Comments'
                  : 'Comments (${widget.comments.length})',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const Spacer(),
            if (widget.canComment && !_composing)
              AleraIconButton(
                tooltip: widget.comments.isEmpty
                    ? 'Start Conversation'
                    : 'Add Comment',
                icon: AleraIcons.add,
                onPressed: _busy ? null : _startComment,
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space8),
        if (_composing) ...<Widget>[
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
            enabled: !_busy,
            minLines: 3,
            maxLines: 8,
            keyboardType: .multiline,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foreground,
            ),
            cursorColor: AleraTokens.foreground,
            decoration: pullRequestFieldDecoration(
              theme,
              hint: 'Add a comment',
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          Row(
            mainAxisAlignment: .end,
            children: <Widget>[
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        _controller.clear();
                        setState(() => _composing = false);
                      },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AleraTokens.space6),
              FilledButton.icon(
                onPressed: _busy ? null : _postComment,
                icon: _posting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AleraIcons.send, size: 16),
                label: const Text('Post Comment'),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space12),
        ],
        if (widget.comments.isEmpty)
          Text(
            'No comments yet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          )
        else
          for (var index = 0; index < widget.comments.length; index++) ...[
            _ReviewCommentCard(
              comment: widget.comments[index],
              onOpenUrl: widget.onOpenUrl,
              taskListEditable:
                  widget.canEditComments &&
                  widget.comments[index].locator != null,
              taskListSaving: widget.savingCommentIds.contains(
                widget.comments[index].id,
              ),
              onTaskListItemToggle: (itemIndex) =>
                  widget.onToggleTask(widget.comments[index].id, itemIndex),
            ),
            if (index != widget.comments.length - 1)
              const SizedBox(height: AleraTokens.space8),
          ],
      ],
    );
  }
}

class const _ReviewCommentCard({
  required final ReviewComment comment,
  required final Future<void> Function(String url) onOpenUrl,
  required final bool taskListEditable,
  required final bool taskListSaving,
  required final Future<void> Function(int itemIndex) onTaskListItemToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = _locationLabel(comment);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    comment.author,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                ),
                Text(
                  _formatTimestamp(context, comment.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
                if (comment.url != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space4),
                  AleraIconButton(
                    tooltip: 'Open Comment',
                    icon: AleraIcons.external,
                    onPressed: () => onOpenUrl(comment.url!),
                  ),
                ],
              ],
            ),
            if (location != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space6),
              Row(
                children: <Widget>[
                  const Icon(
                    AleraIcons.code,
                    size: 13,
                    color: AleraTokens.foregroundFaint,
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                  if (comment.resolved)
                    Text(
                      'Resolved',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.success,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AleraTokens.space8),
            PullRequestCommentMarkdown(
              body: comment.body,
              onOpenUrl: onOpenUrl,
              taskListEditable: taskListEditable,
              taskListSaving: taskListSaving,
              onTaskListItemToggle: onTaskListItemToggle,
            ),
          ],
        ),
      ),
    );
  }

  String? _locationLabel(ReviewComment comment) {
    final path = comment.path;
    if (path == null || path.isEmpty) {
      return null;
    }
    return comment.line == null ? path : '$path:${comment.line}';
  }

  String _formatTimestamp(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '$date · $time';
  }
}

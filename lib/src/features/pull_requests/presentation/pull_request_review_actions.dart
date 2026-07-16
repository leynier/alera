part of 'pull_request_review_view.dart';

class _PullRequestReviewActions extends StatefulWidget {
  const _PullRequestReviewActions({
    required this.review,
    required this.mergeMethods,
    required this.canCloseReview,
    required this.action,
    required this.onMerge,
    required this.onClose,
    required this.onUnlink,
  });

  final HostedReview review;
  final List<ReviewMergeMethod> mergeMethods;
  final bool canCloseReview;
  final PullRequestAction? action;
  final Future<void> Function(ReviewMergeMethod method) onMerge;
  final Future<void> Function() onClose;
  final VoidCallback onUnlink;

  @override
  State<_PullRequestReviewActions> createState() =>
      _PullRequestReviewActionsState();
}

class _PullRequestReviewActionsState extends State<_PullRequestReviewActions> {
  ReviewMergeMethod? _selectedMethod;

  ReviewMergeMethod? get _method {
    final selected = _selectedMethod;
    if (selected != null && widget.mergeMethods.contains(selected)) {
      return selected;
    }
    return widget.mergeMethods.firstOrNull;
  }

  bool get _busy => widget.action != null;

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final method = _method;
    final canMerge =
        review.state == HostedReviewState.open &&
        review.mergeable != HostedReviewMergeable.conflicting &&
        method != null;
    final canClose = review.isOpen && widget.canCloseReview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (review.isOpen) ...<Widget>[
          if (method != null)
            _MergePullRequestButton(
              method: method,
              methods: widget.mergeMethods,
              busy: widget.action == PullRequestAction.merge,
              enabled: canMerge && !_busy,
              onPressed: () => _confirmMerge(method),
              onSelected: (selected) {
                setState(() => _selectedMethod = selected);
                unawaited(_confirmMerge(selected));
              },
            ),
          if (method != null) const SizedBox(height: AleraTokens.space8),
          OutlinedButton.icon(
            onPressed: canClose && !_busy ? _confirmClose : null,
            icon: widget.action == PullRequestAction.close
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    AleraIcons.gitPullRequestClosed,
                    size: 16,
                    color: AleraTokens.error,
                  ),
            label: const Text('Close Pull Request'),
          ),
          const SizedBox(height: AleraTokens.space4),
        ],
        TextButton.icon(
          onPressed: _busy ? null : widget.onUnlink,
          icon: widget.action == PullRequestAction.unlink
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(AleraIcons.unlink, size: 16),
          label: const Text('Unlink Pull Request'),
        ),
      ],
    );
  }

  Future<void> _confirmMerge(ReviewMergeMethod method) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: '${method.label} PR #${widget.review.number}?',
        message:
            'This Will Update The Pull Request On '
            '${widget.review.provider.label}.',
        confirmLabel: method.label,
      ),
    );
    if (confirmed == true) {
      await widget.onMerge(method);
    }
  }

  Future<void> _confirmClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Close Pull Request #${widget.review.number}?',
        message: 'This Will Close The Pull Request Without Merging It.',
        confirmLabel: 'Close Pull Request',
        destructive: true,
      ),
    );
    if (confirmed == true) {
      await widget.onClose();
    }
  }
}

class _MergePullRequestButton extends StatelessWidget {
  const _MergePullRequestButton({
    required this.method,
    required this.methods,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    required this.onSelected,
  });

  final ReviewMergeMethod method;
  final List<ReviewMergeMethod> methods;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;
  final ValueChanged<ReviewMergeMethod> onSelected;

  static const double _height = 34;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: AleraTokens.onAccent);
    final cursor = enabled
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic;
    return MouseRegion(
      cursor: cursor,
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.38,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Material(
            color: AleraTokens.accent,
            child: SizedBox(
              height: _height,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      mouseCursor: cursor,
                      onTap: enabled ? onPressed : null,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (busy)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AleraTokens.onAccent,
                                ),
                              )
                            else
                              const Icon(
                                AleraIcons.gitMerge,
                                size: 16,
                                color: AleraTokens.onAccent,
                              ),
                            const SizedBox(width: AleraTokens.space8),
                            Flexible(
                              child: Text(
                                method.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 0.5,
                    height: 20,
                    color: AleraTokens.onAccent.withValues(alpha: 0.18),
                  ),
                  Tooltip(
                    message: 'Merge Options',
                    child: Builder(
                      builder: (context) => InkWell(
                        mouseCursor: cursor,
                        onTap: enabled
                            ? () => unawaited(_openMenu(context))
                            : null,
                        child: const SizedBox(
                          width: 34,
                          height: _height,
                          child: Icon(
                            AleraIcons.chevronDown,
                            size: 17,
                            color: AleraTokens.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (renderBox == null || overlay is! RenderBox) {
      return;
    }
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<ReviewMergeMethod>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      color: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        side: const BorderSide(color: AleraTokens.border),
      ),
      items: <PopupMenuEntry<ReviewMergeMethod>>[
        for (final option in methods)
          AleraDropdownEntry<ReviewMergeMethod>(
            value: option,
            label: option.label,
            selected: option == method,
            leading: const Icon(AleraIcons.gitMerge, size: 16),
          ),
      ],
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}

part of 'pull_request_review_view.dart';

class _PullRequestReviewActions extends StatefulWidget {
  const _PullRequestReviewActions({
    required this.review,
    required this.mergeMethods,
    required this.canCloseReview,
    required this.canChangeDraftStatus,
    required this.action,
    required this.onMerge,
    required this.onClose,
    required this.onDraftStatusChanged,
    required this.onUnlink,
  });

  final HostedReview review;
  final List<ReviewMergeMethod> mergeMethods;
  final bool canCloseReview;
  final bool canChangeDraftStatus;
  final PullRequestAction? action;
  final Future<void> Function(ReviewMergeMethod method) onMerge;
  final Future<void> Function() onClose;
  final Future<void> Function(bool draft) onDraftStatusChanged;
  final Future<void> Function() onUnlink;

  @override
  State<_PullRequestReviewActions> createState() =>
      _PullRequestReviewActionsState();
}

class _PullRequestReviewActionsState extends State<_PullRequestReviewActions> {
  _PullRequestReviewAction? _selectedAction;

  List<_PullRequestReviewAction> get _availableActions {
    final review = widget.review;
    final actions = <_PullRequestReviewAction>[
      if (review.state == HostedReviewState.draft &&
          widget.canChangeDraftStatus)
        _PullRequestReviewAction.markReady,
      if (review.isOpen)
        ...widget.mergeMethods.map(_PullRequestReviewAction.fromMergeMethod),
      if (review.state == HostedReviewState.open && widget.canChangeDraftStatus)
        _PullRequestReviewAction.convertToDraft,
      if (review.isOpen && widget.canCloseReview)
        _PullRequestReviewAction.close,
      _PullRequestReviewAction.unlink,
    ];
    return actions;
  }

  _PullRequestReviewAction get _action {
    final selected = _selectedAction;
    final actions = _availableActions;
    if (selected != null && actions.contains(selected)) {
      return selected;
    }
    return actions.first;
  }

  bool get _busy => widget.action != null;

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final action = _action;
    final actions = _availableActions;
    final mergeEnabled =
        review.state == HostedReviewState.open &&
        review.mergeable != HostedReviewMergeable.conflicting;
    final primaryEnabled =
        !_busy &&
        switch (action) {
          _PullRequestReviewAction.providerDefault ||
          _PullRequestReviewAction.mergeCommit ||
          _PullRequestReviewAction.squash ||
          _PullRequestReviewAction.rebase => mergeEnabled,
          _PullRequestReviewAction.close =>
            review.isOpen && widget.canCloseReview,
          _PullRequestReviewAction.markReady =>
            review.state == HostedReviewState.draft &&
                widget.canChangeDraftStatus,
          _PullRequestReviewAction.convertToDraft =>
            review.state == HostedReviewState.open &&
                widget.canChangeDraftStatus,
          _PullRequestReviewAction.unlink => true,
        };
    final showProgress = switch (action) {
      _PullRequestReviewAction.providerDefault ||
      _PullRequestReviewAction.mergeCommit ||
      _PullRequestReviewAction.squash ||
      _PullRequestReviewAction.rebase =>
        widget.action == PullRequestAction.merge,
      _PullRequestReviewAction.close =>
        widget.action == PullRequestAction.close,
      _PullRequestReviewAction.markReady ||
      _PullRequestReviewAction.convertToDraft =>
        widget.action == PullRequestAction.draftStatus,
      _PullRequestReviewAction.unlink =>
        widget.action == PullRequestAction.unlink,
    };
    return _PullRequestActionButton(
      action: action,
      actions: actions,
      busy: showProgress,
      primaryEnabled: primaryEnabled,
      menuEnabled: !_busy && actions.length > 1,
      onPressed: () => unawaited(_confirmAction(action)),
      onSelected: (selected) {
        setState(() => _selectedAction = selected);
      },
    );
  }

  Future<void> _confirmAction(_PullRequestReviewAction action) async {
    final method = action.mergeMethod;
    if (method != null) {
      await _confirmMerge(method);
      return;
    }
    switch (action) {
      case _PullRequestReviewAction.close:
        await _confirmClose();
        return;
      case _PullRequestReviewAction.unlink:
        await _confirmUnlink();
        return;
      case _PullRequestReviewAction.markReady:
        await _confirmDraftStatus(draft: false);
        return;
      case _PullRequestReviewAction.convertToDraft:
        await _confirmDraftStatus(draft: true);
        return;
      case _PullRequestReviewAction.providerDefault:
      case _PullRequestReviewAction.mergeCommit:
      case _PullRequestReviewAction.squash:
      case _PullRequestReviewAction.rebase:
        return;
    }
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

  Future<void> _confirmUnlink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Unlink Pull Request #${widget.review.number}?',
        message:
            'This Will Remove The Pull Request Link From This Workspace. '
            'The Pull Request On ${widget.review.provider.label} Will Not Be '
            'Changed.',
        confirmLabel: 'Unlink Pull Request',
      ),
    );
    if (confirmed == true) {
      await widget.onUnlink();
    }
  }

  Future<void> _confirmDraftStatus({required bool draft}) async {
    final label = draft ? 'Convert To Draft' : 'Mark Ready For Review';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: '$label PR #${widget.review.number}?',
        message: draft
            ? 'This Will Convert The Pull Request To Draft On '
                  '${widget.review.provider.label}.'
            : 'This Will Mark The Pull Request As Ready For Review On '
                  '${widget.review.provider.label}.',
        confirmLabel: label,
      ),
    );
    if (confirmed == true) {
      await widget.onDraftStatusChanged(draft);
    }
  }
}

enum _PullRequestReviewAction {
  providerDefault,
  mergeCommit,
  squash,
  rebase,
  markReady,
  convertToDraft,
  close,
  unlink;

  factory _PullRequestReviewAction.fromMergeMethod(ReviewMergeMethod method) {
    return switch (method) {
      ReviewMergeMethod.providerDefault =>
        _PullRequestReviewAction.providerDefault,
      ReviewMergeMethod.mergeCommit => _PullRequestReviewAction.mergeCommit,
      ReviewMergeMethod.squash => _PullRequestReviewAction.squash,
      ReviewMergeMethod.rebase => _PullRequestReviewAction.rebase,
    };
  }

  ReviewMergeMethod? get mergeMethod => switch (this) {
    _PullRequestReviewAction.providerDefault =>
      ReviewMergeMethod.providerDefault,
    _PullRequestReviewAction.mergeCommit => ReviewMergeMethod.mergeCommit,
    _PullRequestReviewAction.squash => ReviewMergeMethod.squash,
    _PullRequestReviewAction.rebase => ReviewMergeMethod.rebase,
    _PullRequestReviewAction.markReady ||
    _PullRequestReviewAction.convertToDraft ||
    _PullRequestReviewAction.close ||
    _PullRequestReviewAction.unlink => null,
  };

  String get label => switch (this) {
    _PullRequestReviewAction.providerDefault =>
      ReviewMergeMethod.providerDefault.label,
    _PullRequestReviewAction.mergeCommit => ReviewMergeMethod.mergeCommit.label,
    _PullRequestReviewAction.squash => ReviewMergeMethod.squash.label,
    _PullRequestReviewAction.rebase => ReviewMergeMethod.rebase.label,
    _PullRequestReviewAction.markReady => 'Mark Ready For Review',
    _PullRequestReviewAction.convertToDraft => 'Convert To Draft',
    _PullRequestReviewAction.close => 'Close Pull Request',
    _PullRequestReviewAction.unlink => 'Unlink Pull Request',
  };

  IconData get icon => switch (this) {
    _PullRequestReviewAction.providerDefault ||
    _PullRequestReviewAction.mergeCommit ||
    _PullRequestReviewAction.squash ||
    _PullRequestReviewAction.rebase => AleraIcons.gitMerge,
    _PullRequestReviewAction.markReady => AleraIcons.success,
    _PullRequestReviewAction.convertToDraft => AleraIcons.edit,
    _PullRequestReviewAction.close => AleraIcons.gitPullRequestClosed,
    _PullRequestReviewAction.unlink => AleraIcons.unlink,
  };

  bool get destructive => this == _PullRequestReviewAction.close;
}

class _PullRequestActionButton extends StatelessWidget {
  const _PullRequestActionButton({
    required this.action,
    required this.actions,
    required this.busy,
    required this.primaryEnabled,
    required this.menuEnabled,
    required this.onPressed,
    required this.onSelected,
  });

  final _PullRequestReviewAction action;
  final List<_PullRequestReviewAction> actions;
  final bool busy;
  final bool primaryEnabled;
  final bool menuEnabled;
  final VoidCallback onPressed;
  final ValueChanged<_PullRequestReviewAction> onSelected;

  static const double _height = 34;

  @override
  Widget build(BuildContext context) {
    final background = action.destructive
        ? AleraTokens.error
        : AleraTokens.accent;
    final foreground = action.destructive
        ? AleraTokens.onError
        : AleraTokens.onAccent;
    final textStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: foreground);
    final primaryCursor = primaryEnabled
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic;
    final menuCursor = menuEnabled
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic;
    return MouseRegion(
      cursor: menuEnabled ? SystemMouseCursors.click : primaryCursor,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Material(
          key: ValueKey<String>('pull-request-action-button-${action.name}'),
          color: background,
          child: SizedBox(
            height: _height,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Opacity(
                    opacity: primaryEnabled || busy ? 1 : 0.38,
                    child: InkWell(
                      mouseCursor: primaryCursor,
                      onTap: primaryEnabled ? onPressed : null,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (busy)
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: foreground,
                                ),
                              )
                            else
                              Icon(action.icon, size: 16, color: foreground),
                            const SizedBox(width: AleraTokens.space8),
                            Flexible(
                              child: Text(
                                action.label,
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
                ),
                if (actions.length > 1) ...<Widget>[
                  Container(
                    width: 0.5,
                    height: 20,
                    color: foreground.withValues(alpha: 0.18),
                  ),
                  Tooltip(
                    message: 'Pull Request Actions',
                    child: Builder(
                      builder: (context) => InkWell(
                        mouseCursor: menuCursor,
                        onTap: menuEnabled
                            ? () => unawaited(_openMenu(context))
                            : null,
                        child: SizedBox(
                          width: 34,
                          height: _height,
                          child: Icon(
                            AleraIcons.chevronDown,
                            size: 17,
                            color: foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
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
    final readyActions = actions.where(
      (option) => option == _PullRequestReviewAction.markReady,
    );
    final mergeActions = actions.where((option) => option.mergeMethod != null);
    final otherActions = actions.where(
      (option) =>
          option.mergeMethod == null &&
          option != _PullRequestReviewAction.markReady,
    );
    final selected = await showMenu<_PullRequestReviewAction>(
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
      items: <PopupMenuEntry<_PullRequestReviewAction>>[
        for (final option in readyActions)
          AleraDropdownEntry<_PullRequestReviewAction>(
            value: option,
            label: option.label,
            selected: option == action,
            leading: Icon(option.icon, size: 16),
          ),
        if (readyActions.isNotEmpty && mergeActions.isNotEmpty)
          const PopupMenuDivider(height: AleraTokens.space8),
        for (final option in mergeActions)
          AleraDropdownEntry<_PullRequestReviewAction>(
            value: option,
            label: option.label,
            selected: option == action,
            leading: Icon(option.icon, size: 16),
          ),
        if ((readyActions.isNotEmpty || mergeActions.isNotEmpty) &&
            otherActions.isNotEmpty)
          const PopupMenuDivider(height: AleraTokens.space8),
        for (final option in otherActions)
          AleraDropdownEntry<_PullRequestReviewAction>(
            value: option,
            label: option.label,
            selected: option == action,
            leading: Icon(
              option.icon,
              size: 16,
              color: option.destructive ? AleraTokens.error : null,
            ),
          ),
      ],
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}

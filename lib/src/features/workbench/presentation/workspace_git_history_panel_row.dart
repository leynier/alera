part of 'workspace_git_diff_panel.dart';

class const _GitHistoryCommitRow({
  required final GitHistoryItemViewModel viewModel,
  required final bool expanded,
  required final VoidCallback? onTap,
  required final void Function(BuildContext context)? onOpenActions,
}) extends StatelessWidget {
  static const double _chevronSlotWidth = 14;
  static const double _actionsButtonWidth = 30;
  static const double _hiddenRefCountWidth = 24;
  static const double _subjectMinWidth = 48;
  static const double _refBadgeMinWidth = 40;
  static const double _refBadgeMaxWidth = 160;

  // The row is a fixed-height single line, so ref badges get an explicit
  // width budget: Flexible would cap the subject even when badges are small,
  // and unbounded badges overflow narrow panels.
  ({int visibleRefCount, double refBadgeMaxWidth}) _refBadgeBudget({
    required double rowWidth,
    required int refCount,
  }) {
    var fixedWidth =
        _GitHistoryGraph.widthFor(viewModel) +
        AleraTokens.space4 +
        _chevronSlotWidth +
        AleraTokens.space4 +
        _subjectMinWidth;
    if (onOpenActions != null) {
      fixedWidth += _actionsButtonWidth;
    }
    var visibleRefCount = refCount > 2 ? 2 : refCount;
    var refBadgeMaxWidth = 0.0;
    while (visibleRefCount > 0) {
      var reserved = fixedWidth + visibleRefCount * AleraTokens.space4;
      if (refCount > visibleRefCount) {
        reserved += AleraTokens.space4 + _hiddenRefCountWidth;
      }
      refBadgeMaxWidth = (rowWidth - reserved) / visibleRefCount;
      if (refBadgeMaxWidth >= _refBadgeMinWidth) {
        break;
      }
      visibleRefCount -= 1;
    }
    return (
      visibleRefCount: visibleRefCount,
      refBadgeMaxWidth: refBadgeMaxWidth.clamp(0.0, _refBadgeMaxWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = viewModel.historyItem;
    final boundary =
        viewModel.kind == GitHistoryItemViewModelKind.incomingChanges ||
        viewModel.kind == GitHistoryItemViewModelKind.outgoingChanges;
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: InkWell(
        onTap: onTap,
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AleraTokens.space8,
              right: AleraTokens.space6,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final budget = _refBadgeBudget(
                  rowWidth: constraints.maxWidth,
                  refCount: item.references.length,
                );
                final hiddenRefCount =
                    item.references.length - budget.visibleRefCount;
                return Row(
                  children: <Widget>[
                    _GitHistoryGraph(viewModel: viewModel),
                    const SizedBox(width: AleraTokens.space4),
                    if (!boundary)
                      Icon(
                        expanded
                            ? AleraIcons.chevronDown
                            : AleraIcons.chevronRight,
                        size: _chevronSlotWidth,
                        color: AleraTokens.foregroundFaint,
                      )
                    else
                      const SizedBox(width: _chevronSlotWidth),
                    const SizedBox(width: AleraTokens.space4),
                    Expanded(
                      child: Text(
                        item.subject,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: boundary
                              ? AleraTokens.foregroundMuted
                              : AleraTokens.foreground,
                        ),
                      ),
                    ),
                    for (final itemRef in item.references.take(
                      budget.visibleRefCount,
                    )) ...<Widget>[
                      const SizedBox(width: AleraTokens.space4),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: budget.refBadgeMaxWidth,
                        ),
                        child: _GitRefBadge(itemRef: itemRef),
                      ),
                    ],
                    if (hiddenRefCount > 0) ...<Widget>[
                      const SizedBox(width: AleraTokens.space4),
                      Text(
                        '+$hiddenRefCount',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AleraTokens.foregroundFaint),
                      ),
                    ],
                    if (onOpenActions != null)
                      Builder(
                        builder: (context) => AleraIconButton(
                          tooltip: 'Commit Actions',
                          icon: AleraIcons.more,
                          onPressed: () => onOpenActions!(context),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class const _GitRefBadge({required final GitHistoryItemRef itemRef})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = _graphColor(itemRef.color);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        border: Border.all(color: color ?? AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space6,
          vertical: AleraTokens.space2,
        ),
        child: Text(
          itemRef.name,
          maxLines: 1,
          overflow: .ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color ?? AleraTokens.foregroundMuted,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

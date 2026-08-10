part of 'codex_chat_surface.dart';

enum _CodexWorkedActionKind {
  review,
  edit,
  read,
  viewImage,
  listFiles,
  search,
  webSearch,
  tool,
  ran,
}

class _CodexWorkedAction {
  const _CodexWorkedAction({
    required this.cell,
    required this.kind,
    required this.label,
    required this.hasDetails,
    this.itemCount = 1,
  });

  final CodexTimelineCell cell;
  final _CodexWorkedActionKind kind;
  final String label;
  final bool hasDetails;
  final int itemCount;

  IconData get icon => switch (kind) {
    _CodexWorkedActionKind.review => AleraIcons.review,
    _CodexWorkedActionKind.edit => AleraIcons.edit,
    _CodexWorkedActionKind.read => AleraIcons.read,
    _CodexWorkedActionKind.viewImage => AleraIcons.viewImage,
    _CodexWorkedActionKind.listFiles => AleraIcons.file,
    _CodexWorkedActionKind.search => AleraIcons.search,
    _CodexWorkedActionKind.webSearch => AleraIcons.public,
    _CodexWorkedActionKind.tool => AleraIcons.devTools,
    _CodexWorkedActionKind.ran => AleraIcons.terminal,
  };
}

final Expando<_CodexWorkedAction> _codexWorkedActionCache =
    Expando<_CodexWorkedAction>('codex worked action');

class _CodexWorkedActionGroup extends StatelessWidget {
  const _CodexWorkedActionGroup({
    required this.projection,
    required this.expanded,
    required this.expandedActions,
    required this.onToggle,
    required this.onToggleAction,
  });

  final _CodexSecondaryRowProjection projection;
  final bool expanded;
  final Set<String> expandedActions;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleAction;

  @override
  Widget build(BuildContext context) {
    final projection = this.projection;
    final actions = projection.actions;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            key: ValueKey<String>(
              'worked-action-group-${actions.first.cell.id}',
            ),
            onTap: onToggle,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space6,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    projection.summaryIcon!,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Flexible(
                    child: projection.streaming
                        ? _CodexShimmerText(
                            key: const ValueKey<String>(
                              'codex-streaming-worked-summary',
                            ),
                            text: projection.summary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AleraTokens.foregroundMuted),
                          )
                        : Text(
                            projection.summary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AleraTokens.foregroundMuted),
                          ),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  Icon(
                    expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: AleraTokens.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final action in actions)
                    _CodexWorkedActionRow(
                      key: ValueKey<String>(
                        'codex-worked-row-${action.cell.id}',
                      ),
                      action: action,
                      expanded: expandedActions.contains(action.cell.id),
                      onToggle: () => onToggleAction(action.cell.id),
                    ),
                  if (projection.waiting) const _CodexWorkedWaitingRow(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CodexWorkedWaitingRow extends StatelessWidget {
  const _CodexWorkedWaitingRow();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('codex-synthetic-worked-waiting'),
    padding: const EdgeInsets.symmetric(
      horizontal: AleraTokens.space6,
      vertical: AleraTokens.space4,
    ),
    child: Row(
      children: <Widget>[
        const Icon(
          AleraIcons.ai,
          size: AleraTokens.iconMd,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space8),
        _CodexShimmerText(
          text: 'Working',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ],
    ),
  );
}

class _CodexWorkedActionRow extends StatelessWidget {
  const _CodexWorkedActionRow({
    super.key,
    required this.action,
    required this.expanded,
    required this.onToggle,
  });

  final _CodexWorkedAction action;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final hasDetails = action.hasDetails;
    final color = action.cell.status == CodexTimelineStatus.failed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          key: ValueKey<String>('worked-action-${action.cell.id}'),
          onTap: hasDetails ? onToggle : null,
          mouseCursor: hasDetails
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space6,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              children: <Widget>[
                Icon(action.icon, size: AleraTokens.iconMd, color: color),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: action.cell.isStreaming
                      ? _CodexShimmerText(
                          text: action.label,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: color),
                        )
                      : Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: color),
                        ),
                ),
                if (!action.cell.isStreaming && hasDetails)
                  Icon(
                    expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
              ],
            ),
          ),
        ),
        if (expanded && hasDetails)
          Container(
            margin: const EdgeInsets.only(
              left: AleraTokens.space24,
              top: AleraTokens.space4,
              bottom: AleraTokens.space4,
            ),
            padding: const EdgeInsets.all(AleraTokens.space8),
            decoration: BoxDecoration(
              color: AleraTokens.surface,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              border: Border.all(color: AleraTokens.borderSubtle),
            ),
            child: _CodexToolDetails(cell: action.cell),
          ),
      ],
    );
  }
}

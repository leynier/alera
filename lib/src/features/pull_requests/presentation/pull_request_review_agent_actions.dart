part of 'pull_request_review_view.dart';

class const _PullRequestCheckAgentHeader({
  required this.checkCount,
  required this.checksFailed,
  required this.reviewIsOpen,
  required this.busy,
  required this.watchMode,
  required this.onFixFailedChecks,
  required this.onWatchAndFix,
  required this.onWatchFixAndMerge,
  required this.onStopAgentWatch,
}) extends StatelessWidget {
  final int checkCount;
  final bool checksFailed;
  final bool reviewIsOpen;
  final bool busy;
  final PullRequestAgentWatchMode? watchMode;
  final VoidCallback? onFixFailedChecks;
  final VoidCallback? onWatchAndFix;
  final VoidCallback? onWatchFixAndMerge;
  final VoidCallback? onStopAgentWatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final watching = watchMode != null;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            checkCount == 0 ? 'Checks' : 'Checks ($checkCount)',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        if (reviewIsOpen && !busy)
          if (watching)
            _watchingActions(theme)
          else
            _idleActions(context, theme),
      ],
    );
  }

  Widget _idleActions(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (checksFailed && onFixFailedChecks != null)
          TextButton(
            onPressed: onFixFailedChecks,
            child: const Text('Fix Failed Checks'),
          ),
        if (onWatchAndFix != null || onWatchFixAndMerge != null)
          Builder(
            builder: (buttonContext) => AleraIconButton(
              tooltip: 'Ask Agent',
              icon: AleraIcons.agent,
              onPressed: () => unawaited(_openWatchMenu(buttonContext)),
            ),
          ),
      ],
    );
  }

  Widget _watchingActions(ThemeData theme) {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        Flexible(
          child: Text(
            pullRequestAgentWatchModeLabel(watchMode!),
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        if (onStopAgentWatch != null)
          TextButton(
            onPressed: onStopAgentWatch,
            child: const Text('Stop Watching'),
          ),
      ],
    );
  }

  Future<void> _openWatchMenu(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (renderBox == null || overlay is! RenderBox) {
      return;
    }
    final topLeft = renderBox.localToGlobal(.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<_WatchMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      color: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        side: const BorderSide(color: AleraTokens.border),
      ),
      items: <PopupMenuEntry<_WatchMenuAction>>[
        if (onWatchAndFix != null)
          const AleraDropdownEntry<_WatchMenuAction>(
            value: .watchAndFix,
            label: 'Watch and Fix',
            leading: Icon(AleraIcons.agent, size: 16),
          ),
        if (onWatchFixAndMerge != null)
          const AleraDropdownEntry<_WatchMenuAction>(
            value: .watchFixAndMerge,
            label: 'Watch, Fix and Merge',
            leading: Icon(AleraIcons.gitMerge, size: 16),
          ),
      ],
    );
    switch (selected) {
      case _WatchMenuAction.watchAndFix:
        onWatchAndFix?.call();
      case _WatchMenuAction.watchFixAndMerge:
        onWatchFixAndMerge?.call();
      case null:
        break;
    }
  }
}

enum _WatchMenuAction { watchAndFix, watchFixAndMerge }

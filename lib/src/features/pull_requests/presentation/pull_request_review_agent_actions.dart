part of 'pull_request_review_view.dart';

/// Checks section title plus the one-shot failed-checks dispatch, hidden while
/// a watch already owns that work.
class const _PullRequestCheckAgentHeader({
  required this.checkCount,
  required this.checksFailed,
  required this.reviewIsOpen,
  required this.busy,
  required this.watching,
  required this.onFixFailedChecks,
}) extends StatelessWidget {
  final int checkCount;
  final bool checksFailed;
  final bool reviewIsOpen;
  final bool busy;
  final bool watching;
  final VoidCallback? onFixFailedChecks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        if (reviewIsOpen &&
            !busy &&
            !watching &&
            checksFailed &&
            onFixFailedChecks != null)
          TextButton(
            onPressed: onFixFailedChecks,
            child: const Text('Fix Failed Checks'),
          ),
      ],
    );
  }
}

/// Header control for Watch and Fix. Idle, it opens the watch scope and the
/// watch modes; while watching, it offers Stop Watching.
class const _PullRequestWatchAgentButton({
  required this.reviewIsOpen,
  required this.busy,
  required this.watchMode,
  required this.watchScope,
  required this.onWatchScopeChanged,
  required this.onWatchAndFix,
  required this.onWatchFixAndMerge,
  required this.onStopAgentWatch,
}) extends StatelessWidget {
  final bool reviewIsOpen;
  final bool busy;
  final PullRequestAgentWatchMode? watchMode;
  final PullRequestAgentWatchScope watchScope;
  final ValueChanged<PullRequestAgentWatchScope>? onWatchScopeChanged;
  final ValueChanged<PullRequestAgentWatchScope>? onWatchAndFix;
  final ValueChanged<PullRequestAgentWatchScope>? onWatchFixAndMerge;
  final VoidCallback? onStopAgentWatch;

  @override
  Widget build(BuildContext context) {
    final mode = watchMode;
    if (mode != null) {
      return Builder(
        builder: (buttonContext) => AleraIconButton(
          tooltip: pullRequestAgentWatchModeLabel(mode),
          icon: AleraIcons.visible,
          onPressed: onStopAgentWatch == null
              ? null
              : () => unawaited(_openWatchingMenu(buttonContext)),
        ),
      );
    }
    if (!reviewIsOpen ||
        (onWatchAndFix == null && onWatchFixAndMerge == null)) {
      return const SizedBox.shrink();
    }
    return Builder(
      builder: (buttonContext) => AleraIconButton(
        tooltip: 'Ask Agent',
        icon: AleraIcons.agent,
        onPressed: busy ? null : () => unawaited(_openWatchMenu(buttonContext)),
      ),
    );
  }

  Future<void> _openWatchingMenu(BuildContext context) async {
    final selected = await _showAnchoredMenu<_WatchMenuAction>(
      context,
      const <PopupMenuEntry<_WatchMenuAction>>[
        AleraDropdownEntry<_WatchMenuAction>(
          value: .stop,
          label: 'Stop Watching',
          leading: Icon(AleraIcons.hidden, size: 16),
        ),
      ],
    );
    if (selected == _WatchMenuAction.stop) {
      onStopAgentWatch?.call();
    }
  }

  Future<void> _openWatchMenu(BuildContext context) async {
    var scope = watchScope;
    void update(PullRequestAgentWatchScope next) {
      scope = next;
      onWatchScopeChanged?.call(next);
    }

    final selected = await _showAnchoredMenu<_WatchMenuAction>(
      context,
      <PopupMenuEntry<_WatchMenuAction>>[
        AleraDropdownToggleEntry<_WatchMenuAction>(
          label: 'Failed Checks',
          checked: scope.checks,
          onChanged: (value) => update(scope.copyWith(checks: value)),
        ),
        AleraDropdownToggleEntry<_WatchMenuAction>(
          label: 'Review Comments',
          checked: scope.comments,
          onChanged: (value) => update(scope.copyWith(comments: value)),
        ),
        AleraDropdownToggleEntry<_WatchMenuAction>(
          label: 'Merge Conflicts',
          checked: scope.conflicts,
          onChanged: (value) => update(scope.copyWith(conflicts: value)),
        ),
        const PopupMenuDivider(),
        if (onWatchAndFix != null)
          AleraDropdownEntry<_WatchMenuAction>(
            value: .watchAndFix,
            label: 'Watch and Fix',
            enabled: !watchScope.isEmpty,
            leading: const Icon(AleraIcons.agent, size: 16),
          ),
        if (onWatchFixAndMerge != null)
          AleraDropdownEntry<_WatchMenuAction>(
            value: .watchFixAndMerge,
            label: 'Watch, Fix and Merge',
            enabled: !watchScope.isEmpty,
            leading: const Icon(AleraIcons.gitMerge, size: 16),
          ),
      ],
    );
    switch (selected) {
      case _WatchMenuAction.watchAndFix:
        onWatchAndFix?.call(scope);
      case _WatchMenuAction.watchFixAndMerge:
        onWatchFixAndMerge?.call(scope);
      case _WatchMenuAction.stop:
      case null:
        break;
    }
  }
}

/// Status line under the pull request title while a watch is running.
class const _PullRequestWatchStatus({required this.mode})
    extends StatelessWidget {
  final PullRequestAgentWatchMode mode;

  @override
  Widget build(BuildContext context) {
    return Text(
      pullRequestAgentWatchModeLabel(mode),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}

Future<T?> _showAnchoredMenu<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> items,
) async {
  final renderBox = context.findRenderObject() as RenderBox?;
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  if (renderBox == null || overlay is! RenderBox) {
    return null;
  }
  final topLeft = renderBox.localToGlobal(.zero, ancestor: overlay);
  final bottomRight = renderBox.localToGlobal(
    renderBox.size.bottomRight(.zero),
    ancestor: overlay,
  );
  return showMenu<T>(
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
    items: items,
  );
}

enum _WatchMenuAction { watchAndFix, watchFixAndMerge, stop }

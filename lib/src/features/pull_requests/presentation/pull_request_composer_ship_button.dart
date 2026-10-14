part of 'pull_request_composer.dart';

/// Outlined split button for Ship, shaped like [_CreatePullRequestButton].
///
/// The main segment ships with the remembered [followUp]. The chevron only
/// picks that follow-up and the problems Watch reacts to; it never ships.
class const _ShipPullRequestButton({
  required final PullRequestShipFollowUp followUp,
  required final PullRequestAgentWatchScope watchScope,
  required final bool shipping,
  required final bool aiEnabled,
  required final bool enabled,
  required final bool menuEnabled,
  required final VoidCallback onPressed,
  required final ValueChanged<PullRequestShipFollowUp> onFollowUpChanged,
  required final ValueChanged<PullRequestAgentWatchScope> onWatchScopeChanged,
}) extends StatelessWidget {
  String get _label => switch (followUp) {
    _ when shipping => 'Shipping Changes',
    PullRequestShipFollowUp.none => 'Ship Changes',
    PullRequestShipFollowUp.watchAndFix => 'Ship and Watch',
    PullRequestShipFollowUp.watchFixAndMerge => 'Ship and Merge',
  };

  String get _tooltip => switch (followUp) {
    _ when !aiEnabled =>
      'Enable AI Assist to ship local commits or staged changes',
    PullRequestShipFollowUp.none =>
      'Ship local commits or staged changes and create a pull request',
    PullRequestShipFollowUp.watchAndFix =>
      'Ship, then watch the pull request and have an agent fix problems',
    PullRequestShipFollowUp.watchFixAndMerge =>
      'Ship a ready pull request, have an agent fix problems, and merge it '
          'once it is green',
  };

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AleraTokens.accent : AleraTokens.foregroundFaint;
    final textStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: color);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            height: _CreatePullRequestButton._height,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Tooltip(
                    message: _tooltip,
                    child: InkWell(
                      key: const Key('pull-request-ship-button'),
                      mouseCursor: enabled
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onTap: enabled ? onPressed : null,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: _CreatePullRequestButton._trailingWidth,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: .min,
                            children: <Widget>[
                              if (shipping)
                                const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Icon(
                                  pullRequestShipFollowUpIcon(followUp),
                                  size: 15,
                                  color: color,
                                ),
                              const SizedBox(width: AleraTokens.space8),
                              Flexible(
                                child: Text(
                                  _label,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: textStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 0.5, height: 18, color: AleraTokens.border),
                Tooltip(
                  message: 'Ship Options',
                  child: Builder(
                    builder: (context) => InkWell(
                      key: const Key('pull-request-ship-options'),
                      mouseCursor: menuEnabled
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onTap: menuEnabled
                          ? () => unawaited(_openMenu(context))
                          : null,
                      child: SizedBox(
                        width: 34,
                        height: _CreatePullRequestButton._height,
                        child: Icon(
                          AleraIcons.chevronDown,
                          size: 17,
                          color: menuEnabled
                              ? AleraTokens.accent
                              : AleraTokens.foregroundFaint,
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
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (renderBox == null || overlay is! RenderBox) {
      return;
    }
    final scope = ValueNotifier<PullRequestAgentWatchScope>(watchScope);
    final topLeft = renderBox.localToGlobal(.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<PullRequestShipFollowUp>(
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
      items: pullRequestShipMenuEntries<PullRequestShipFollowUp>(
        valueOf: (value) => value,
        selected: followUp,
        scope: scope,
        onScopeChanged: onWatchScopeChanged,
      ),
    );
    scope.dispose();
    if (selected != null) {
      onFollowUpChanged(selected);
    }
  }
}

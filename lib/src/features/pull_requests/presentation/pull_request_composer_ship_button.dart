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
  static String menuLabel(PullRequestShipFollowUp followUp) =>
      switch (followUp) {
        PullRequestShipFollowUp.none => 'Ship Changes',
        PullRequestShipFollowUp.watchAndFix => 'Ship, Watch and Fix',
        PullRequestShipFollowUp.watchFixAndMerge =>
          'Ship, Watch, Fix and Merge',
      };

  static IconData icon(PullRequestShipFollowUp followUp) => switch (followUp) {
    PullRequestShipFollowUp.none => AleraIcons.send,
    PullRequestShipFollowUp.watchAndFix => AleraIcons.agent,
    PullRequestShipFollowUp.watchFixAndMerge => AleraIcons.gitMerge,
  };

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
                                Icon(icon(followUp), size: 15, color: color),
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
    // The menu route never rebuilds from this widget, so the watch rows listen
    // to the scope the toggles edit instead of the value the menu opened with.
    final scope = ValueNotifier<PullRequestAgentWatchScope>(watchScope);
    void update(PullRequestAgentWatchScope next) {
      scope.value = next;
      onWatchScopeChanged(next);
    }

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
      items: <PopupMenuEntry<PullRequestShipFollowUp>>[
        for (final value in PullRequestShipFollowUp.values)
          _ShipFollowUpMenuEntry(
            value: value,
            selected: value == followUp,
            scope: scope,
          ),
        const PopupMenuDivider(),
        AleraDropdownToggleEntry<PullRequestShipFollowUp>(
          label: 'Failed Checks',
          checked: scope.value.checks,
          onChanged: (value) => update(scope.value.copyWith(checks: value)),
        ),
        AleraDropdownToggleEntry<PullRequestShipFollowUp>(
          label: 'Review Comments',
          checked: scope.value.comments,
          onChanged: (value) => update(scope.value.copyWith(comments: value)),
        ),
        AleraDropdownToggleEntry<PullRequestShipFollowUp>(
          label: 'Merge Conflicts',
          checked: scope.value.conflicts,
          onChanged: (value) => update(scope.value.copyWith(conflicts: value)),
        ),
      ],
    );
    scope.dispose();
    if (selected != null) {
      onFollowUpChanged(selected);
    }
  }
}

/// A follow-up row. The watch follow-ups are only selectable while [scope] has
/// something to watch.
class const _ShipFollowUpMenuEntry({
  required this.value,
  required this.selected,
  required this.scope,
}) extends PopupMenuEntry<PullRequestShipFollowUp> {
  final PullRequestShipFollowUp value;
  final bool selected;
  final ValueNotifier<PullRequestAgentWatchScope> scope;

  @override
  double get height => 36;

  @override
  bool represents(PullRequestShipFollowUp? value) => false;

  @override
  State<_ShipFollowUpMenuEntry> createState() => _ShipFollowUpMenuEntryState();
}

class _ShipFollowUpMenuEntryState extends State<_ShipFollowUpMenuEntry> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PullRequestAgentWatchScope>(
      valueListenable: widget.scope,
      builder: (context, scope, _) =>
          AleraDropdownEntry<PullRequestShipFollowUp>(
            value: widget.value,
            label: _ShipPullRequestButton.menuLabel(widget.value),
            selected: widget.selected,
            enabled: !widget.value.watches || !scope.isEmpty,
            leading: Icon(_ShipPullRequestButton.icon(widget.value), size: 16),
          ),
    );
  }
}

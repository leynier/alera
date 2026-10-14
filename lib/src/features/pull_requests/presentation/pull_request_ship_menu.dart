import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_toggle_entry.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_follow_up.dart';
import 'package:flutter/material.dart';

String pullRequestShipFollowUpLabel(PullRequestShipFollowUp followUp) =>
    switch (followUp) {
      PullRequestShipFollowUp.none => 'Ship Changes',
      PullRequestShipFollowUp.watchAndFix => 'Ship, Watch and Fix',
      PullRequestShipFollowUp.watchFixAndMerge => 'Ship, Watch, Fix and Merge',
    };

IconData pullRequestShipFollowUpIcon(PullRequestShipFollowUp followUp) =>
    switch (followUp) {
      PullRequestShipFollowUp.none => AleraIcons.send,
      PullRequestShipFollowUp.watchAndFix => AleraIcons.agent,
      PullRequestShipFollowUp.watchFixAndMerge => AleraIcons.gitMerge,
    };

/// The Ship follow-ups, a divider, and the problems Watch reacts to, for any
/// menu that offers shipping. [scope] holds the live watch scope: the menu
/// route never rebuilds from its caller, so the follow-up rows listen to it
/// and turn off while nothing is watched. [onScopeChanged] receives every
/// toggle after [scope] is updated.
List<PopupMenuEntry<T>> pullRequestShipMenuEntries<T>({
  required T Function(PullRequestShipFollowUp followUp) valueOf,
  required PullRequestShipFollowUp selected,
  required ValueNotifier<PullRequestAgentWatchScope> scope,
  required ValueChanged<PullRequestAgentWatchScope> onScopeChanged,
  bool enabled = true,
}) {
  void update(PullRequestAgentWatchScope next) {
    scope.value = next;
    onScopeChanged(next);
  }

  return <PopupMenuEntry<T>>[
    for (final followUp in PullRequestShipFollowUp.values)
      _ShipFollowUpEntry<T>(
        value: valueOf(followUp),
        followUp: followUp,
        selected: followUp == selected,
        enabled: enabled,
        scope: scope,
      ),
    const PopupMenuDivider(),
    AleraDropdownToggleEntry<T>(
      label: 'Failed Checks',
      checked: scope.value.checks,
      onChanged: (value) => update(scope.value.copyWith(checks: value)),
    ),
    AleraDropdownToggleEntry<T>(
      label: 'Review Comments',
      checked: scope.value.comments,
      onChanged: (value) => update(scope.value.copyWith(comments: value)),
    ),
    AleraDropdownToggleEntry<T>(
      label: 'Merge Conflicts',
      checked: scope.value.conflicts,
      onChanged: (value) => update(scope.value.copyWith(conflicts: value)),
    ),
  ];
}

/// A follow-up row. The watch follow-ups are only selectable while [scope]
/// has something to watch.
class const _ShipFollowUpEntry<T>({
  required this.value,
  required this.followUp,
  required this.selected,
  required this.enabled,
  required this.scope,
}) extends PopupMenuEntry<T> {
  final T value;
  final PullRequestShipFollowUp followUp;
  final bool selected;
  final bool enabled;
  final ValueNotifier<PullRequestAgentWatchScope> scope;

  @override
  double get height => 36;

  @override
  bool represents(T? value) => false;

  @override
  State<_ShipFollowUpEntry<T>> createState() => _ShipFollowUpEntryState<T>();
}

class _ShipFollowUpEntryState<T> extends State<_ShipFollowUpEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PullRequestAgentWatchScope>(
      valueListenable: widget.scope,
      builder: (context, scope, _) => AleraDropdownEntry<T>(
        value: widget.value,
        label: pullRequestShipFollowUpLabel(widget.followUp),
        selected: widget.selected,
        enabled: widget.enabled && (!widget.followUp.watches || !scope.isEmpty),
        leading: Icon(pullRequestShipFollowUpIcon(widget.followUp), size: 16),
      ),
    );
  }
}

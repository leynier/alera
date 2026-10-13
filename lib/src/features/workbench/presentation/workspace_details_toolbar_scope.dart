import 'package:flutter/material.dart';

/// Lets terminal controls share the workspace overlay without owning its state.
class const WorkspaceDetailsToolbarScope({
  super.key,
  required super.child,
  required final ValueChanged<bool> onAvailabilityChanged,
  required final ValueChanged<BuildContext> onToggle,
}) extends InheritedWidget {
  static WorkspaceDetailsToolbarScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkspaceDetailsToolbarScope>();

  @override
  bool updateShouldNotify(WorkspaceDetailsToolbarScope oldWidget) =>
      onAvailabilityChanged != oldWidget.onAvailabilityChanged ||
      onToggle != oldWidget.onToggle;
}

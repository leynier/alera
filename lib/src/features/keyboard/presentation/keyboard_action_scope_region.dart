import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:flutter/widgets.dart';

/// Marks a subtree as a [KeyboardActionScope] surface, so bindings scoped to
/// it resolve while the focus is inside. [target] names the instance, such as
/// the chat id, so the dispatcher acts on the surface that holds the focus
/// rather than on the active tab.
class const KeyboardActionScopeRegion({
  super.key,
  required final KeyboardActionScope scope,
  final String? target,
  required super.child,
}) extends InheritedWidget {
  /// The region around the primary focus, if any.
  static KeyboardActionScopeRegion? ofPrimaryFocus() => FocusManager
      .instance
      .primaryFocus
      ?.context
      ?.getInheritedWidgetOfExactType<KeyboardActionScopeRegion>();

  @override
  bool updateShouldNotify(KeyboardActionScopeRegion oldWidget) => false;
}

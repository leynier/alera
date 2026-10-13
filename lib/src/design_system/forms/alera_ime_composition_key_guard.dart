import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps Enter and Escape away from the shortcuts above [child] while
/// [controller] holds text an input method has not committed yet.
///
/// The desktop embedders offer a key to the framework before the input
/// method, so a send or close shortcut bound above a text field would take
/// the Enter that confirms an IME candidate, or the Escape that cancels it.
/// Skipping the remaining handlers reports the key as unhandled, which hands
/// it to the input method. Place the guard between the field and those
/// shortcuts.
class const AleraImeCompositionKeyGuard({
  super.key,
  required final TextEditingController controller,
  required final Widget child,
}) extends StatelessWidget {
  static const List<LogicalKeyboardKey> _compositionKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.escape,
  ];

  /// Whether [value] holds uncommitted input method text.
  static bool isComposing(TextEditingValue value) =>
      value.isComposingRangeValid && !value.composing.isCollapsed;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent ||
        !_compositionKeys.contains(event.logicalKey) ||
        !isComposing(controller.value)) {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.skipRemainingHandlers;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }
}

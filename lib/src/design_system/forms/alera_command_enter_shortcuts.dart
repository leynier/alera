import 'package:flutter/material.dart';

/// Runs [onCommandEnter] for Control+Enter and Cmd+Enter.
///
/// Plain Enter is left to the child, so multiline fields can still insert a
/// newline. The [CallbackShortcuts] wrapper stays in the tree when the
/// callback is null so toggling submission does not remount the field.
class const AleraCommandEnterShortcuts({
  super.key,
  required this.onCommandEnter,
  required this.child,
}) extends StatelessWidget {
  final VoidCallback? onCommandEnter;
  final Widget child;

  static const SingleActivator controlEnter = SingleActivator(
    .enter,
    control: true,
    includeRepeats: false,
  );

  static const SingleActivator metaEnter = SingleActivator(
    .enter,
    meta: true,
    includeRepeats: false,
  );

  @override
  Widget build(BuildContext context) {
    final onCommandEnter = this.onCommandEnter;
    return CallbackShortcuts(
      bindings: onCommandEnter == null
          ? const <ShortcutActivator, VoidCallback>{}
          : <ShortcutActivator, VoidCallback>{
              controlEnter: onCommandEnter,
              metaEnter: onCommandEnter,
            },
      child: child,
    );
  }
}

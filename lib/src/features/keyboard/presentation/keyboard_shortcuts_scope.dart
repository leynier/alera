import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide keyboard shortcut layer for everything outside a focused terminal.
///
/// A focused terminal handles its own keys (and intercepts Alera shortcuts via
/// [TerminalSurface]), so those events never bubble here. When focus is on the
/// sidebar, a dialog, or no editable field, unhandled chords bubble up to this
/// ancestor and are dispatched.
///
/// This is a [FocusScope] rather than a plain [Focus] so that focus which
/// falls off the content (a focused widget unmounts and nothing else claims
/// it) lands on this node instead of the route scope above it. Key events are
/// only delivered to the primary focus and its ancestors, so focus parked on
/// the route would put every shortcut out of reach.
class const KeyboardShortcutsScope({super.key, required final Widget child})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FocusScope(
      debugLabel: 'KeyboardShortcutsScope',
      skipTraversal: true,
      onKeyEvent: (node, event) => _handleKey(context, ref, event),
      child: child,
    );
  }

  KeyEventResult _handleKey(
    BuildContext context,
    WidgetRef ref,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = ref.read(settingsControllerProvider).keyboard;
    final resolver = KeybindingResolver(settings: keyboard);
    final modifiers = KeyModifierState.fromKeyboard(.instance);
    final resolved = resolver.resolveAction(event, modifiers);
    if (resolved == null) {
      return KeyEventResult.ignored;
    }
    KeyboardCommandDispatcher(ref: ref, context: context).dispatch(resolved.id);
    return KeyEventResult.handled;
  }
}

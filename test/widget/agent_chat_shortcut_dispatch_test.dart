import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_shortcut_targets.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_shortcuts_scope.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DefaultSettings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

void main() {
  testWidgets('a chat chord no focused chat can use is left unhandled', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(_DefaultSettings.new),
      ],
    );
    addTearDown(container.dispose);
    final asked = <AgentChatShortcut>[];
    var accept = false;
    bool handler(AgentChatShortcut shortcut) {
      asked.add(shortcut);
      return accept;
    }

    container.read(agentChatShortcutTargetsProvider).register(handler);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: KeyboardShortcutsScope(
              child: Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Future<bool> altUp() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      return handled;
    }

    // Alt+Up is Edit Last Queued Message by default; the shortcut layer
    // lets it go when the chat declines, so a text field keeps the key.
    final declined = await altUp();
    accept = true;
    final taken = await altUp();
    expect(asked, <AgentChatShortcut>[
      AgentChatShortcut.editLastQueued,
      AgentChatShortcut.editLastQueued,
    ]);
    expect(taken, isTrue);
    expect(declined, isFalse);

    container.read(agentChatShortcutTargetsProvider).unregister(handler);
    accept = false;
    await altUp();
    expect(asked.length, 2);
  });
}

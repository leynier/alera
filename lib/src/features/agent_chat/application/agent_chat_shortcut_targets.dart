import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_shortcut_targets.g.dart';

/// Chat keyboard actions the dispatcher hands to the chat that has focus.
enum AgentChatShortcut {
  increaseEffort,
  decreaseEffort,
  cycleMode,
  stop,
  editLastQueued,
  steerNextQueued,
}

/// Answers whether a mounted chat acted on [shortcut].
typedef AgentChatShortcutHandler = bool Function(AgentChatShortcut shortcut);

/// The chats on screen that can take a chat shortcut. Unlike the composer
/// commands, the answer is synchronous: a chord no focused chat can use is
/// left to the field that has the caret (Alt+Up still moves it).
final class AgentChatShortcutTargets {
  final List<AgentChatShortcutHandler> _handlers = <AgentChatShortcutHandler>[];

  void register(AgentChatShortcutHandler handler) => _handlers.add(handler);

  void unregister(AgentChatShortcutHandler handler) =>
      _handlers.remove(handler);

  /// Whether a chat with the keyboard focus took [shortcut].
  bool run(AgentChatShortcut shortcut) {
    for (final handler in List.of(_handlers)) {
      if (handler(shortcut)) return true;
    }
    return false;
  }
}

@Riverpod(keepAlive: true)
AgentChatShortcutTargets agentChatShortcutTargets(Ref ref) =>
    AgentChatShortcutTargets();

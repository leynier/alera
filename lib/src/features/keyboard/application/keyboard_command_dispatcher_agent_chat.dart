part of 'keyboard_command_dispatcher.dart';

/// Actions on the agent chat on screen.
extension _KeyboardCommandDispatcherAgentChat on KeyboardCommandDispatcher {
  /// Opens the agent and model picker of the active chat tab; elsewhere the
  /// chord does nothing.
  void _chooseAgentChatModel() {
    final tab = ref.read(workbenchControllerProvider).activeWorkspaceTab;
    final chatId = tab?.kind == WorkspaceTabKind.agentChat
        ? tab!.agentChatId
        : null;
    if (chatId == null) return;
    ref.read(agentChatComposerCommandsProvider.notifier).chooseModel(chatId);
  }

  /// Hands a chat action to the chat with the keyboard focus; `false` when
  /// none could act, so the key reaches the focused field.
  bool _runAgentChatShortcut(KeyboardActionId id) {
    final shortcut = _agentChatShortcutFor(id);
    return shortcut != null &&
        ref.read(agentChatShortcutTargetsProvider).run(shortcut);
  }

  AgentChatShortcut? _agentChatShortcutFor(KeyboardActionId id) => switch (id) {
    KeyboardActionId.increaseAgentChatEffort =>
      AgentChatShortcut.increaseEffort,
    KeyboardActionId.decreaseAgentChatEffort =>
      AgentChatShortcut.decreaseEffort,
    KeyboardActionId.cycleAgentChatMode => AgentChatShortcut.cycleMode,
    KeyboardActionId.stopAgentChatTurn => AgentChatShortcut.stop,
    KeyboardActionId.editLastQueuedMessage => AgentChatShortcut.editLastQueued,
    KeyboardActionId.steerNextQueuedMessage =>
      AgentChatShortcut.steerNextQueued,
    _ => null,
  };

  /// Opens find in the focused chat, or in the active chat tab when the
  /// command palette runs it.
  void _findInAgentChat() {
    final tab = ref.read(workbenchControllerProvider).activeWorkspaceTab;
    final chatId =
        scopeTarget ??
        (tab?.kind == WorkspaceTabKind.agentChat ? tab!.agentChatId : null);
    if (chatId == null) return;
    ref.read(agentChatFindRequestsProvider.notifier).open(chatId);
  }
}

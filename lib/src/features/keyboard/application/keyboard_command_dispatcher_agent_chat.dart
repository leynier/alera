part of 'keyboard_command_dispatcher.dart';

/// Commands that act on one agent chat.
extension _KeyboardCommandDispatcherAgentChat on KeyboardCommandDispatcher {
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

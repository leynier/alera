part of 'agent_chat_tab_view.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _AgentChatTabReadCursor on _AgentChatTabViewState {
  /// The person is looking at this chat: tell the runtime, once output has
  /// paused, so the other devices stop calling it unread.
  void _scheduleChatRead(AgentChatViewState view, bool visible) {
    if (!visible || view.thread.cursor == 0) return;
    _readTimer?.cancel();
    _readTimer = Timer(_AgentChatTabViewState._readDebounce, () {
      if (!mounted) return;
      unawaited(
        ref.read(_provider.notifier).markRead().catchError((Object error) {
          _AgentChatTabViewState._logger.fine(
            'Could not mark the chat read.',
            error,
          );
        }),
      );
    });
  }
}

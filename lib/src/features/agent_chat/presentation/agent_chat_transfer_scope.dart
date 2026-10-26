import 'package:flutter/widgets.dart';

/// What a chat tab lets its context transfer rows do: open the chat the
/// context came from.
class AgentChatTransferScope extends InheritedWidget {
  const AgentChatTransferScope({
    super.key,
    required this.onOpenChat,
    required super.child,
  });

  final ValueChanged<String> onOpenChat;

  static AgentChatTransferScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentChatTransferScope>();

  @override
  bool updateShouldNotify(AgentChatTransferScope oldWidget) =>
      onOpenChat != oldWidget.onOpenChat;
}

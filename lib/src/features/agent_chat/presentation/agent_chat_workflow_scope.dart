import 'package:flutter/widgets.dart';

/// The chat a workflow view reads from, and whether the runtime serves a
/// workflow's script and member answers (`agentChatWorkflowsV1`).
class AgentChatWorkflowScope extends InheritedWidget {
  const AgentChatWorkflowScope({
    super.key,
    required this.chatId,
    required this.workspaceId,
    required this.readable,
    required super.child,
  });

  final String chatId;
  final String workspaceId;
  final bool readable;

  static AgentChatWorkflowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentChatWorkflowScope>();

  @override
  bool updateShouldNotify(AgentChatWorkflowScope oldWidget) =>
      chatId != oldWidget.chatId ||
      workspaceId != oldWidget.workspaceId ||
      readable != oldWidget.readable;
}

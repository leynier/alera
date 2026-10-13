import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_status_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';

/// The workbench content of an `agentChat` tab.
class const AgentChatTabSurface({
  super.key,
  required final Workspace workspace,
  required final WorkspaceTabRecord tab,
  final bool autofocus = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final chatId = tab.agentChatId;
    if (chatId == null) return const AgentChatUnboundView();
    return AgentChatSurface(
      key: ValueKey<String>('agent-chat-surface-$chatId'),
      chatId: chatId,
      workspace: workspace,
      fallbackTitle: tab.title,
      fallbackProvider: tab.agentChatProvider ?? '',
      autofocus: autofocus,
    );
  }
}

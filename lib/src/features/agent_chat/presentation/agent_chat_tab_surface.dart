import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_status_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_action_scope_region.dart';
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
    // Chat-scoped shortcuts, such as Find in Chat, apply while the focus
    // is anywhere in the chat: the timeline, the find bar or the composer.
    return KeyboardActionScopeRegion(
      scope: KeyboardActionScope.agentChat,
      target: chatId,
      child: AgentChatSurface(
        key: ValueKey<String>('agent-chat-surface-$chatId'),
        chatId: chatId,
        workspace: workspace,
        fallbackTitle: tab.title,
        fallbackProvider: tab.agentChatProvider ?? '',
        autofocus: autofocus,
      ),
    );
  }
}

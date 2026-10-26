import 'package:alera/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_preview_card.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// T3 Code's sidebar thread hover card on a chat's workbench tab: the chat's
/// agent, state and last activity, and the chat it was forked or delegated
/// from. Shows nothing until the runtime lists the chat.
class const AgentChatTabHover({
  super.key,
  required final String chatId,
  required final Widget child,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats =
        ref.watch(agentChatRelatedChatsProvider).value ??
        const <AgentChatSummary>[];
    final chat = chats.where((chat) => chat.chatId == chatId).firstOrNull;
    if (chat == null) return child;
    return AgentChatPreviewHover(
      preview: AgentChatPreview.chat(
        chat,
        fallbackTitle: 'Agent Chat',
        relation: agentChatOriginLabel(chat, chats),
        providerLabel: agentChatProviderFallbackLabel,
      ),
      child: child,
    );
  }
}

/// "Forked from `chat`" or "Delegated by `chat`", or null for a chat that
/// started on its own.
String? agentChatOriginLabel(
  AgentChatSummary chat,
  List<AgentChatSummary> chats,
) {
  String title(String id) {
    final related = chats.where((other) => other.chatId == id).firstOrNull;
    final text = related?.title.trim() ?? '';
    return text.isEmpty ? 'another chat' : text;
  }

  if (chat.forkedFromChatId case final source?) {
    return 'Forked from ${title(source)}';
  }
  if (chat.parentChatId case final parent?) {
    return 'Delegated by ${title(parent)}';
  }
  return null;
}

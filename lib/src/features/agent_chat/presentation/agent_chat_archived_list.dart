import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A workspace's archived chats, each of which can come back in a new tab
/// with its history.
class const AgentChatArchivedList({
  super.key,
  required final List<AgentChatSummary> chats,
  required final String? reopeningChatId,
  required final ValueChanged<AgentChatSummary> onReopen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    return AleraCollapsibleSection(
      title: 'Archived Chats',
      initiallyExpanded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final chat in chats)
            Padding(
              key: ValueKey<String>('agent-chat-archived-${chat.chatId}'),
              padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
              child: Row(
                children: <Widget>[
                  AgentChatProviderIcon(provider: chat.provider),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          chat.title.isEmpty ? 'Untitled Chat' : chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          localizations.formatMediumDate(
                            chat.updatedAt.toLocal(),
                          ),
                          style: AleraTokens.labelMicroFaintStyle,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: reopeningChatId == null
                        ? () => onReopen(chat)
                        : null,
                    child: Text(
                      reopeningChatId == chat.chatId ? 'Reopening' : 'Reopen',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Loads the archived chats of [workspaceId] once for the dialog.
Future<List<AgentChatSummary>> loadArchivedAgentChats(
  AgentChatRepository repository,
  String workspaceId,
) async {
  final chats = await repository.list(
    workspaceId: workspaceId,
    includeArchived: true,
  );
  return <AgentChatSummary>[
    for (final chat in chats)
      if (chat.archived) chat,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

/// Keeps the reopen request id stable per chat for the dialog's lifetime,
/// so a retried reopen returns the same tab.
final class AgentChatReopenIds {
  AgentChatReopenIds(this._nextId);

  final String Function() _nextId;
  final Map<String, String> _ids = <String, String>{};

  String forChat(String chatId) => _ids.putIfAbsent(chatId, _nextId);
}

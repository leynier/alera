import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'agent_chat_tab_actions.g.dart';

/// Tab-level actions on a chat, for the workspace tab strip.
class AgentChatTabActions(
  final String _hostId,
  final AgentChatRepository _repository,
  final AgentChatDraftStore _drafts,
) {
  /// Archives the chat on the runtime: its provider stops and the history is
  /// kept, so Reopen can bring it back. The tab goes away with it.
  Future<void> close({
    required String workspaceId,
    required String chatId,
  }) async {
    await _repository.close(
      AgentChatRef(chatId: chatId, workspaceId: workspaceId),
      requestId: const Uuid().v4(),
    );
    _drafts.close(_hostId, chatId);
  }

  /// The chat title is the tab title; renaming one renames the other.
  Future<void> rename({
    required String workspaceId,
    required String chatId,
    required String title,
  }) => _repository.rename(
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    requestId: const Uuid().v4(),
    title: title.trim(),
  );
}

@riverpod
Future<AgentChatTabActions> agentChatTabActions(Ref ref, String hostId) async =>
    AgentChatTabActions(
      hostId,
      await ref.watch(agentChatRepositoryProvider(hostId).future),
      ref.watch(agentChatDraftStoreProvider),
    );

// The package's orchestration AgentChatRequestIds is a different concept.
import 'package:alera_agent_chat/alera_agent_chat.dart'
    hide AgentChatRequestIds;
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_request_ids.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'agent_chat_tab_actions.g.dart';

/// Tab-level actions on a chat, for the workspace tab strip.
class AgentChatTabActions(
  final String _hostId,
  final AgentChatRepository _repository,
  final AgentChatDraftStore _drafts,
  final AgentChatRequestIds _requestIds,
  final AgentChatViewMemoryStore _memory,
) {
  /// Closes the chat on the runtime. A chat with history is archived, its
  /// provider stopped and its history kept for Reopen; a chat nothing was
  /// ever sent to is discarded, so the archive only holds real work. The
  /// tab goes away either way.
  Future<AgentChatCloseResult> close({
    required String workspaceId,
    required String chatId,
  }) async {
    final chat = AgentChatRef(chatId: chatId, workspaceId: workspaceId);
    final requestId = _requestIds.claimClose(_hostId, chatId);
    final AgentChatCloseResult result;
    try {
      result = await _closeOn(chat, requestId);
    } on AgentChatConnectionException {
      rethrow;
    } on Object {
      _requestIds.settleClose(_hostId, chatId);
      rethrow;
    }
    _requestIds.settleClose(_hostId, chatId);
    _drafts.close(_hostId, chatId);
    _memory.forget(_hostId, chatId);
    return result;
  }

  Future<AgentChatCloseResult> _closeOn(
    AgentChatRef chat,
    String requestId,
  ) async {
    try {
      return await _repository.lifecycle.close(chat, requestId: requestId);
    } on UnsupportedError {
      // A repository without the lifecycle service still closes chats; it
      // only cannot say whether the runtime discarded one.
      await _repository.close(chat, requestId: requestId);
      return const AgentChatCloseResult(archived: true);
    }
  }

  /// Reopens an archived chat in a new tab. One id per chat until the
  /// runtime answers, so a retried Reopen cannot open it twice.
  Future<AgentChatOpenResult> reopen({
    required String workspaceId,
    required String chatId,
  }) async {
    final requestId = _requestIds.claimReopen(_hostId, chatId);
    try {
      final result = await _repository.reopen(
        AgentChatRef(chatId: chatId, workspaceId: workspaceId),
        requestId: requestId,
      );
      _requestIds.settleReopen(_hostId, chatId);
      _drafts.activate(_hostId, chatId);
      return result;
    } on AgentChatConnectionException {
      rethrow;
    } on Object {
      _requestIds.settleReopen(_hostId, chatId);
      rethrow;
    }
  }

  /// Removes an archived chat and its history from the host for good.
  Future<bool> delete({
    required String workspaceId,
    required String chatId,
  }) async {
    final deleted = await _repository.lifecycle.delete(
      AgentChatRef(chatId: chatId, workspaceId: workspaceId),
      requestId: const Uuid().v4(),
    );
    if (deleted) {
      _drafts.close(_hostId, chatId);
      _memory.forget(_hostId, chatId);
    }
    return deleted;
  }

  /// The chat title is the tab title; renaming one renames the other, and
  /// the runtime stops titling the chat by itself from then on.
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
      ref.watch(agentChatRequestIdsProvider),
      ref.watch(agentChatViewMemoryStoreProvider),
    );

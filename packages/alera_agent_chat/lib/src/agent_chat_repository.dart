import 'package:alera_agent_chat/src/agent_chat_change.dart';
import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';
import 'package:alera_agent_chat/src/agent_chat_summary.dart';

/// What a chat's live stream reports besides changes.
sealed class AgentChatStreamEvent {
  const AgentChatStreamEvent();
}

final class AgentChatChangeReceived extends AgentChatStreamEvent {
  const AgentChatChangeReceived(this.change);

  final AgentChatChange change;
}

/// The connection came back, or a change could not be read: the local copy
/// may be behind and must be replaced by a fresh snapshot.
final class AgentChatResyncRequired extends AgentChatStreamEvent {
  const AgentChatResyncRequired();
}

/// The connection dropped. The last copy stays readable but stale until
/// [AgentChatResyncRequired] arrives.
final class AgentChatConnectionLost extends AgentChatStreamEvent {
  const AgentChatConnectionLost();
}

/// A chat list may have changed. [workspaceId] scopes it; `null` means any.
final class AgentChatListChanged {
  const AgentChatListChanged([this.workspaceId]);

  final String? workspaceId;
}

/// Identifies a chat for chat-scoped verbs. The workspace routes the request
/// to the host that owns the chat when the workspace is remote.
final class const AgentChatRef({
  required final String chatId,
  required final String workspaceId,
});

/// Everything the apps read from and ask of agent chats. Mutations carry a
/// caller-allocated id so a retry after a dropped connection replays the
/// runtime's stored receipt instead of acting twice.
abstract interface class AgentChatRepository {
  /// Whether the runtime advertises agent chats at all.
  Future<bool> supported();

  Future<List<AgentChatProviderInstance>> providers({
    String? workspaceId,
    bool refreshModels = false,
  });

  Future<List<AgentChatSummary>> list({
    String? workspaceId,
    bool includeArchived = false,
  });

  Stream<AgentChatListChanged> watchList();

  Future<AgentChatOpenResult> create(AgentChatCreateInput input);

  /// Reopens an archived chat in a new tab.
  Future<AgentChatOpenResult> reopen(
    AgentChatRef chat, {
    required String requestId,
  });

  Future<AgentChatSnapshot> snapshot(AgentChatRef chat);

  Future<AgentChatHistoryPage> history(
    AgentChatRef chat, {
    required String before,
    int? limit,
  });

  /// Changes for [chatId] in arrival order, plus connection transitions.
  /// Subscribe before reading the snapshot so nothing falls in between.
  Stream<AgentChatStreamEvent> watch(String chatId);

  Future<AgentChatSendResult> send(AgentChatSendInput input);

  /// Returns whether the entry was still queued.
  Future<bool> cancelQueued(
    AgentChatRef chat, {
    required String requestId,
    required String queueId,
  });

  Future<void> interrupt(
    AgentChatRef chat, {
    required String requestId,
    String? turnId,
  });

  Future<void> respond(
    AgentChatRef chat, {
    required String requestId,
    required String runtimeRequestId,
    required AgentChatResponse response,
  });

  Future<AgentChatSnapshot> configure(
    AgentChatRef chat, {
    required String requestId,
    required AgentChatConfiguration configuration,
  });

  Future<String> rename(
    AgentChatRef chat, {
    required String requestId,
    required String title,
  });

  Future<AgentChatSnapshot> recover(
    AgentChatRef chat, {
    required String requestId,
    AgentChatRecoverMode? mode,
  });

  /// Archives the chat and stops its provider process; history is kept.
  Future<void> close(AgentChatRef chat, {required String requestId});
}

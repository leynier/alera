import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_relationships.g.dart';

/// A sub-agent's transcript as the runtime stores it, so work on pages the
/// chat has not loaded still shows. Live items come from the chat itself.
@riverpod
Future<AgentChatSubagentTranscript> agentChatSubagentTranscript(
  Ref ref,
  String hostId,
  String workspaceId,
  String chatId,
  String callId,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  return repository.lifecycle.subagent(
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    itemId: callId,
  );
}

/// Every chat the paired runtime knows, archived ones included, for the
/// lineage sheet: a parent or fork may live in another workspace.
@riverpod
Future<List<AgentChatSummary>> agentChatRelatedChats(
  Ref ref,
  String hostId,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  final subscription = repository.watchList().listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(subscription.cancel);
  return repository.list(includeArchived: true);
}

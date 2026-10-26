import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_relationships.g.dart';

/// The provider-native sub-agent a chat tab shows in place of the chat, by
/// the call that started it; `null` shows the chat itself.
@riverpod
class AgentChatOpenSubagent extends _$AgentChatOpenSubagent {
  @override
  String? build(String chatId) => null;

  void open(String callId) => state = callId;

  void close() => state = null;
}

/// A sub-agent's transcript as the runtime stores it, so work on pages the
/// chat has not loaded still shows. Live items come from the chat itself.
@riverpod
Future<AgentChatSubagentTranscript> agentChatSubagentTranscript(
  Ref ref,
  String chatId,
  String workspaceId,
  String callId,
) => ref
    .watch(agentChatLifecycleRepositoryProvider)
    .subagent(
      AgentChatRef(chatId: chatId, workspaceId: workspaceId),
      itemId: callId,
    );

/// Every chat the runtime knows, archived ones included, for the
/// relationships control: a parent or fork may live in another workspace.
@riverpod
Future<List<AgentChatSummary>> agentChatRelatedChats(Ref ref) async {
  final repository = ref.watch(agentChatRepositoryProvider);
  final subscription = repository.watchList().listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(() => unawaited(subscription.cancel()));
  return repository.list(includeArchived: true);
}

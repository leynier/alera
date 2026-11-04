import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_workflows.g.dart';

/// The script the workflow a call started runs (`agentChatWorkflowsV1`).
@riverpod
Future<AgentChatWorkflowScript> agentChatWorkflowScript(
  Ref ref,
  String hostId,
  String workspaceId,
  String chatId,
  String callId,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  return repository.lifecycle.workflowScript(
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    itemId: callId,
  );
}

/// What one member of that workflow answered, from its transcript.
@riverpod
Future<List<String>> agentChatWorkflowAnswers(
  Ref ref,
  String hostId,
  String workspaceId,
  String chatId,
  String callId,
  int agentIndex,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  return repository.lifecycle.workflowAgent(
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    itemId: callId,
    agentIndex: agentIndex,
  );
}

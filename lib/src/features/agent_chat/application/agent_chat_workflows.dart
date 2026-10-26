import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_workflows.g.dart';

/// The script the workflow a call started runs (`agentChatWorkflowsV1`).
@riverpod
Future<AgentChatWorkflowScript> agentChatWorkflowScript(
  Ref ref,
  String chatId,
  String workspaceId,
  String callId,
) => ref
    .watch(agentChatLifecycleRepositoryProvider)
    .workflowScript(
      AgentChatRef(chatId: chatId, workspaceId: workspaceId),
      itemId: callId,
    );

/// What one member of that workflow answered, from its transcript.
@riverpod
Future<List<String>> agentChatWorkflowAnswers(
  Ref ref,
  String chatId,
  String workspaceId,
  String callId,
  int agentIndex,
) => ref
    .watch(agentChatLifecycleRepositoryProvider)
    .workflowAgent(
      AgentChatRef(chatId: chatId, workspaceId: workspaceId),
      itemId: callId,
      agentIndex: agentIndex,
    );

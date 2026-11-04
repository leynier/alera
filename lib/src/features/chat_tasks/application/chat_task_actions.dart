import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_task_actions.g.dart';

@riverpod
AgentChatTaskActions chatTaskActions(Ref ref) => AgentChatTaskActions(
  ref.watch(chatTaskRepositoryProvider),
  ref.watch(agentChatIdGeneratorProvider),
);

import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_automation_agent_chats.g.dart';

/// The open agent chats of [workspaceId] on [hostId] an automation can post
/// into, most recently updated first. A change to the chat list reads them
/// again.
@riverpod
Future<List<AgentChatSummary>> mobileAutomationAgentChats(
  Ref ref,
  String hostId,
  String workspaceId,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  final subscription = repository.watchList().listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(() => unawaited(subscription.cancel()));
  final chats = await repository.list(workspaceId: workspaceId);
  return <AgentChatSummary>[
    for (final chat in chats)
      if (!chat.archived && chat.workspaceId == workspaceId) chat,
  ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
}

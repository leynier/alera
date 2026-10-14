import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/infra/runtime_host_agent_chat_transport.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_parent_activity.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_workspace_attention.g.dart';

/// Every unarchived chat the runtime lists, across workspaces, kept current
/// by the shared [AgentChatAttentionTracker].
@Riverpod(keepAlive: true)
class ChatAttentionEntries extends _$ChatAttentionEntries {
  @override
  Map<String, ChatAttentionEntry> build() {
    final tracker = AgentChatAttentionTracker(
      repository: ref.watch(agentChatRepositoryProvider),
      events: RuntimeHostAgentChatTransport(
        ref.watch(runtimeHostClientProvider),
      ).events,
      clock: ref.watch(agentChatClockProvider),
      onChanged: (entries) {
        if (ref.mounted) state = entries;
      },
    );
    ref.onDispose(() => unawaited(tracker.dispose()));
    tracker.start();
    return const <String, ChatAttentionEntry>{};
  }
}

/// The chats with live child task counts merged in, since the runtime's list
/// only refreshes them on its next read. On a runtime without chat tasks the
/// list's own counts stand.
@Riverpod(keepAlive: true)
Map<String, ChatAttentionEntry> chatAttentionLive(Ref ref) {
  final entries = ref.watch(chatAttentionEntriesProvider);
  if (ref.watch(chatTasksSupportedProvider).value != true) return entries;
  final parents = ref.watch(chatTaskParentActivityProvider);
  ChatAttentionEntry live(ChatAttentionEntry entry) {
    final activity = parents[entry.chatId] ?? ChatTaskParentActivity.none;
    return entry.withChildren((
      open: activity.open,
      needsInput: activity.childNeedsInput,
    ));
  }

  return Map<String, ChatAttentionEntry>.unmodifiableOf(
    <String, ChatAttentionEntry>{
      for (final MapEntry(:key, :value) in entries.entries) key: live(value),
    },
  );
}

/// What each workspace's chats want, for its sidebar row and the Agent
/// Activity sort. Workspaces whose chats are idle are absent.
@Riverpod(keepAlive: true)
Map<String, ChatWorkspaceAttention> chatWorkspaceAttention(Ref ref) =>
    chatWorkspaceAttentionOf(ref.watch(chatAttentionLiveProvider).values);

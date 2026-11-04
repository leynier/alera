import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/mobile_agent_chat_transport.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_chat_agent_presence.g.dart';

/// Every unarchived chat on [hostId], kept current by the same tracker the
/// desktop uses, so workspace rows can list chats beside terminal agents.
/// Empty against a runtime without agent chats.
@riverpod
class MobileChatAttentionEntries extends _$MobileChatAttentionEntries {
  @override
  Map<String, ChatAttentionEntry> build(String hostId) {
    if (ref.watch(agentChatSupportedProvider(hostId)).value != true) {
      return const <String, ChatAttentionEntry>{};
    }
    final client = ref.watch(mobileAgentChatClientProvider(hostId)).value;
    if (client == null) return const <String, ChatAttentionEntry>{};
    final transport = MobileAgentChatTransport(client);
    final tracker = AgentChatAttentionTracker(
      repository: RuntimeAgentChatRepository(transport),
      events: transport.events,
      clock: DateTime.now,
      onChanged: (entries) {
        if (ref.mounted) state = entries;
      },
    );
    ref.onDispose(() => unawaited(tracker.dispose()));
    tracker.start();
    return const <String, ChatAttentionEntry>{};
  }
}

/// The chats of every workspace as agent rows: each delegated chat right
/// after the chat that delegated it when both live in the same workspace,
/// so several chats in one workspace each keep their own tree. A child that
/// needs input in the same workspace carries the request; its parent reads
/// as waiting on it, so one request is not shown twice.
List<AgentPresenceSummary> chatAgentPresence(
  Iterable<ChatAttentionEntry> chats,
) {
  final byWorkspace = <String, List<ChatAttentionEntry>>{};
  for (final chat in chats) {
    byWorkspace.putIfAbsent(chat.workspaceId, () => []).add(chat);
  }
  final covered = <String>{
    for (final group in byWorkspace.values)
      ...chatParentsWithListedChildInput(group),
  };
  final rows = <AgentPresenceSummary>[
    for (final chat in chats)
      if (chat.tabId case final tabId? when tabId.isNotEmpty)
        _presenceFor(chat, tabId, chat.levelAmong(covered)),
  ];
  final byChat = <String, AgentPresenceSummary>{
    for (final row in rows) row.chatId!: row,
  };
  bool nested(AgentPresenceSummary row) {
    final parent = row.parentChatId;
    return parent != null &&
        parent != row.chatId &&
        byChat[parent]?.workspaceId == row.workspaceId;
  }

  final children = <String, List<AgentPresenceSummary>>{};
  for (final row in rows) {
    if (nested(row)) {
      children.putIfAbsent(row.parentChatId!, () => []).add(row);
    }
  }
  final ordered = <AgentPresenceSummary>[];
  final placed = <String>{};
  void place(AgentPresenceSummary row, int depth) {
    if (!placed.add(row.chatId!)) return;
    ordered.add(row.atDepth(depth));
    for (final child in children[row.chatId] ?? const []) {
      place(child, depth + 1);
    }
  }

  for (final row in rows) {
    if (!nested(row)) place(row, 0);
  }
  // Chats only reachable through a cycle have no root above them.
  for (final row in rows) {
    place(row, 0);
  }
  return ordered;
}

AgentPresenceSummary _presenceFor(
  ChatAttentionEntry chat,
  String tabId,
  ChatAttentionLevel level,
) {
  final provider = agentChatProviderName(chat.provider);
  return AgentPresenceSummary(
    terminalSessionId: '',
    workspaceId: chat.workspaceId,
    tabId: tabId,
    agentType: agentChatAgentType(chat.provider),
    state: switch (level) {
      ChatAttentionLevel.needsInput => 'waiting',
      ChatAttentionLevel.working ||
      ChatAttentionLevel.waitingOnTasks => 'working',
      ChatAttentionLevel.failed ||
      ChatAttentionLevel.unread ||
      ChatAttentionLevel.idle => 'done',
    },
    stateStartedAt: chat.updatedAt,
    updatedAt: chat.updatedAt,
    lastAssistantMessage: [
      if (provider != 'the agent') provider,
      mobileChatStateLabel(level),
      if (chat.openChildTaskCount > 0)
        '${chat.openChildTaskCount} delegated '
            '${chat.openChildTaskCount == 1 ? 'task' : 'tasks'}',
    ].join(' · '),
    interrupted: level == ChatAttentionLevel.failed ? true : null,
    title: chat.title,
    chatId: chat.chatId,
    parentChatId: chat.parentChatId,
  );
}

String mobileChatStateLabel(ChatAttentionLevel level) => switch (level) {
  ChatAttentionLevel.needsInput => 'Needs input',
  ChatAttentionLevel.failed => 'Stopped',
  ChatAttentionLevel.unread => 'Unread result',
  ChatAttentionLevel.working => 'Working',
  ChatAttentionLevel.waitingOnTasks => 'Waiting on delegated tasks',
  ChatAttentionLevel.idle => 'Idle',
};

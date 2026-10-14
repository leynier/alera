import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/infra/runtime_host_agent_chat_transport.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_parent_activity.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_workspace_attention.g.dart';

/// Every unarchived chat the runtime lists, across workspaces, so the sidebar
/// and attention notices see chats whose tab is not open. One `agentChat.list`
/// without a workspace seeds it; session and request changes fold in place,
/// and a list change, a settled turn, a deletion or a reconnect reads again.
@Riverpod(keepAlive: true)
class ChatAttentionEntries extends _$ChatAttentionEntries {
  final Map<String, ChatAttentionEntry> _entries =
      <String, ChatAttentionEntry>{};
  int _generation = 0;
  Timer? _reload;

  // Collapses a burst of settled turns and list changes into one read.
  static const Duration _reloadDelay = Duration(milliseconds: 400);

  static const List<String> _attentionKeys = <String>[
    'session',
    'requests',
    'title',
    'archived',
  ];

  @override
  Map<String, ChatAttentionEntry> build() {
    final repository = ref.watch(agentChatRepositoryProvider);
    final clock = ref.watch(agentChatClockProvider);
    final transport = RuntimeHostAgentChatTransport(
      ref.watch(runtimeHostClientProvider),
    );
    final subscription = transport.events.listen((event) {
      switch (event.name) {
        case AgentChatWire.changedEvent:
          _apply(event.payload, repository, clock());
        case AgentChatWire.listChangedEvent ||
            AgentChatWire.deletedEvent ||
            AgentChatTransportEvents.connected:
          _scheduleReload(repository);
      }
    });
    ref.onDispose(() {
      _generation += 1;
      _reload?.cancel();
      unawaited(subscription.cancel());
    });
    unawaited(_read(repository));
    return const <String, ChatAttentionEntry>{};
  }

  void _scheduleReload(AgentChatRepository repository) {
    _reload?.cancel();
    _reload = Timer(_reloadDelay, () => unawaited(_read(repository)));
  }

  Future<void> _read(AgentChatRepository repository) async {
    final generation = ++_generation;
    try {
      if (!await repository.supported()) return;
      final chats = await repository.list();
      if (!ref.mounted || generation != _generation) return;
      _entries
        ..clear()
        ..addEntries(<MapEntry<String, ChatAttentionEntry>>[
          for (final chat in chats)
            if (!chat.archived)
              MapEntry(chat.chatId, ChatAttentionEntry.fromSummary(chat)),
        ]);
      _publish();
    } on Object {
      // Attention marks are a convenience; each chat reports its own reads.
    }
  }

  void _apply(
    Map<String, Object?> payload,
    AgentChatRepository repository,
    DateTime now,
  ) {
    if (!ref.mounted) return;
    // Streamed text arrives as many changes per second across every chat;
    // only the few that carry state this map keeps are worth parsing.
    final delta = payload['delta'];
    if (delta is! Map || !_attentionKeys.any(delta.containsKey)) return;
    final AgentChatChange change;
    try {
      change = AgentChatChange.fromJson(payload);
    } on FormatException {
      _scheduleReload(repository);
      return;
    }
    final current = _entries[change.chatId];
    if (current == null) {
      if (change.session != null) _scheduleReload(repository);
      return;
    }
    if (change.archived == true) {
      _entries.remove(change.chatId);
      _publish();
      return;
    }
    final next = current.folded(change, now);
    if (next == current) return;
    _entries[change.chatId] = next;
    _publish();
    // A turn that settled may have left an unread result or finished the
    // last child task; only the runtime's list knows.
    if (current.level == ChatAttentionLevel.working &&
        next.level != ChatAttentionLevel.working) {
      _scheduleReload(repository);
    }
  }

  void _publish() =>
      state = Map<String, ChatAttentionEntry>.unmodifiableOf(_entries);
}

/// The chats with live child task counts merged in, since the runtime's list
/// only refreshes them on its next read. On a runtime without chat tasks the
/// list's own counts stand.
@riverpod
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
@riverpod
Map<String, ChatWorkspaceAttention> chatWorkspaceAttention(Ref ref) =>
    chatWorkspaceAttentionOf(ref.watch(chatAttentionLiveProvider).values);

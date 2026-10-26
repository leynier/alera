import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab_activity.dart';
import 'package:alera/src/features/agent_chat/infra/runtime_host_agent_chat_transport.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_workspace_activity.g.dart';

typedef _ChatState = ({AgentChatSessionStatus status, bool hasPendingRequests});

/// The activity of every chat in a workspace, so a chat tab that is not open
/// still shows that its agent is working or waits on the person. Seeded from
/// `agentChat.list` and kept current from each chat's session and request
/// changes; any list change or reconnect reads the list again.
@riverpod
class AgentChatWorkspaceActivity extends _$AgentChatWorkspaceActivity {
  final Map<String, _ChatState> _chats = <String, _ChatState>{};
  int _generation = 0;

  @override
  Map<String, AgentChatTabActivity> build(String workspaceId) {
    final repository = ref.watch(agentChatRepositoryProvider);
    final transport = RuntimeHostAgentChatTransport(
      ref.watch(runtimeHostClientProvider),
    );
    final subscription = transport.events.listen((event) {
      switch (event.name) {
        case AgentChatWire.changedEvent
            when event.payload['workspaceId'] == workspaceId:
          try {
            _apply(AgentChatChange.fromJson(event.payload));
          } on FormatException {
            unawaited(_reload(repository));
          }
        case AgentChatWire.listChangedEvent
            when event.payload['workspaceId'] == null ||
                event.payload['workspaceId'] == workspaceId:
          unawaited(_reload(repository));
        case AgentChatTransportEvents.connected:
          unawaited(_reload(repository));
      }
    });
    ref.onDispose(() {
      _generation += 1;
      unawaited(subscription.cancel());
    });
    unawaited(_reload(repository));
    return const <String, AgentChatTabActivity>{};
  }

  Future<void> _reload(AgentChatRepository repository) async {
    final generation = ++_generation;
    try {
      if (!await repository.supported()) return;
      final chats = await repository.list(workspaceId: workspaceId);
      if (!ref.mounted || generation != _generation) return;
      _chats
        ..clear()
        ..addEntries(<MapEntry<String, _ChatState>>[
          for (final chat in chats)
            if (!chat.archived)
              MapEntry(chat.chatId, (
                status: chat.status,
                hasPendingRequests: chat.pendingRequestCount > 0,
              )),
        ]);
      _publish();
    } on Object {
      // The dots are a convenience; the chat itself reports read failures.
    }
  }

  void _apply(AgentChatChange change) {
    if (!ref.mounted) return;
    if (change.session == null && change.requests == null) return;
    final current =
        _chats[change.chatId] ??
        (status: AgentChatSessionStatus.ready, hasPendingRequests: false);
    final next = agentChatFoldChange(current, change);
    if (next == current) return;
    _chats[change.chatId] = next;
    _publish();
  }

  void _publish() {
    state = Map<String, AgentChatTabActivity>.unmodifiable(
      <String, AgentChatTabActivity>{
        for (final entry in _chats.entries)
          entry.key: agentChatTabActivity(
            entry.value.status,
            hasPendingRequests: entry.value.hasPendingRequests,
          ),
      },
    );
  }
}

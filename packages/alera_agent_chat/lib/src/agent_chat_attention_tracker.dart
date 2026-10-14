import 'dart:async';

import 'package:alera_agent_chat/src/agent_chat_attention_entry.dart';
import 'package:alera_agent_chat/src/agent_chat_change.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_wire.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// Every unarchived chat a runtime lists, across workspaces, so workspace
/// rows and attention notices see chats whose tab is not open. One
/// `agentChat.list` without a workspace seeds it; session, request and title
/// changes fold in place, and a list change, a delegated task change, a
/// settled turn, a deletion or a reconnect reads again. Desktop and phone
/// wrap the same tracker.
final class AgentChatAttentionTracker {
  AgentChatAttentionTracker({
    required AgentChatRepository repository,
    required Stream<AgentChatTransportEvent> events,
    required DateTime Function() clock,
    required void Function(Map<String, ChatAttentionEntry> entries) onChanged,
  }) : _repository = repository,
       _events = events,
       _clock = clock,
       _onChanged = onChanged;

  final AgentChatRepository _repository;
  final Stream<AgentChatTransportEvent> _events;
  final DateTime Function() _clock;
  final void Function(Map<String, ChatAttentionEntry>) _onChanged;
  final Map<String, ChatAttentionEntry> _entries =
      <String, ChatAttentionEntry>{};
  StreamSubscription<AgentChatTransportEvent>? _subscription;
  Timer? _reload;
  int _generation = 0;
  bool _disposed = false;

  // Collapses a burst of settled turns and list changes into one read.
  static const Duration reloadDelay = Duration(milliseconds: 400);

  static const List<String> _attentionKeys = <String>[
    'session',
    'requests',
    'title',
    'archived',
  ];

  Map<String, ChatAttentionEntry> get entries =>
      Map<String, ChatAttentionEntry>.unmodifiableOf(_entries);

  void start() {
    _subscription ??= _events.listen((event) {
      switch (event.name) {
        case AgentChatWire.changedEvent:
          _apply(event.payload);
        case AgentChatWire.listChangedEvent ||
            AgentChatWire.deletedEvent ||
            AgentChatOrchestrationWire.changedEvent ||
            AgentChatTransportEvents.connected:
          _scheduleReload();
      }
    });
    unawaited(_read());
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation += 1;
    _reload?.cancel();
    await _subscription?.cancel();
  }

  void _scheduleReload() {
    if (_disposed) return;
    _reload?.cancel();
    _reload = Timer(reloadDelay, () => unawaited(_read()));
  }

  Future<void> _read() async {
    final generation = ++_generation;
    try {
      if (!await _repository.supported()) return;
      final chats = await _repository.list();
      if (_disposed || generation != _generation) return;
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

  void _apply(Map<String, Object?> payload) {
    if (_disposed) return;
    // Streamed text arrives as many changes per second across every chat;
    // only the few that carry state this map keeps are worth parsing.
    final delta = payload['delta'];
    if (delta is! Map || !_attentionKeys.any(delta.containsKey)) return;
    final AgentChatChange change;
    try {
      change = AgentChatChange.fromJson(payload);
    } on FormatException {
      _scheduleReload();
      return;
    }
    final current = _entries[change.chatId];
    if (current == null) {
      if (change.session != null) _scheduleReload();
      return;
    }
    if (change.archived == true) {
      _entries.remove(change.chatId);
      _publish();
      return;
    }
    final next = current.folded(change, _clock());
    if (next == current) return;
    _entries[change.chatId] = next;
    _publish();
    // A turn that settled may have left an unread result or finished the
    // last child task; only the runtime's list knows.
    if (current.level == ChatAttentionLevel.working &&
        next.level != ChatAttentionLevel.working) {
      _scheduleReload();
    }
  }

  void _publish() => _onChanged(entries);
}

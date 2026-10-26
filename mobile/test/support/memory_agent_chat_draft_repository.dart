import 'dart:async';

import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_repository.dart';

final class MemoryAgentChatDraftRepository implements AgentChatDraftRepository {
  final Map<AgentChatDraftKey, String> snapshots = {};
  Completer<String?>? loadGate;
  bool failSave = false;
  bool failLoad = false;
  int saves = 0;

  @override
  Future<String?> load(AgentChatDraftKey key) async {
    if (failLoad) throw StateError('storage unavailable');
    return loadGate == null ? snapshots[key] : loadGate!.future;
  }

  @override
  Future<void> save(AgentChatDraftKey key, String? snapshot) async {
    saves += 1;
    if (failSave) throw StateError('storage unavailable');
    if (snapshot == null) {
      snapshots.remove(key);
    } else {
      snapshots[key] = snapshot;
    }
  }
}

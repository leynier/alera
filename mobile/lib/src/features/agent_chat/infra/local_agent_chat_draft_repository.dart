import 'dart:convert';

import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class LocalAgentChatDraftRepository({SharedPreferencesAsync? preferences})
    implements AgentChatDraftRepository {
  this : _injected = preferences;

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync get _preferences =>
      _injected ?? SharedPreferencesAsync();

  @override
  Future<String?> load(AgentChatDraftKey key) =>
      _preferences.getString(_scope(key));

  @override
  Future<void> save(AgentChatDraftKey key, String? snapshot) async {
    if (snapshot == null) {
      await _preferences.remove(_scope(key));
    } else {
      await _preferences.setString(_scope(key), snapshot);
    }
  }

  String _scope(AgentChatDraftKey key) =>
      'alera.mobile.agentChatDraft.${jsonEncode(<String>[key.hostId, key.workspaceId, key.chatId])}';
}

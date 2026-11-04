typedef AgentChatDraftKey = ({
  String hostId,
  String workspaceId,
  String chatId,
});

abstract interface class AgentChatDraftRepository {
  Future<String?> load(AgentChatDraftKey key);
  Future<void> save(AgentChatDraftKey key, String? snapshot);
}

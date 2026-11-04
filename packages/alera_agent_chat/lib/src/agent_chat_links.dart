import 'package:alera_agent_chat/src/agent_chat_repository.dart';

/// The scheme of the ready links chat tools return for a chat:
/// `alera-chat://v1/<chatId>?workspace=<workspaceId>`.
const String agentChatLinkScheme = 'alera-chat';

/// The chat an `alera-chat` link names, or null for any other link or one
/// without its workspace.
AgentChatRef? agentChatRefFromLink(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null || uri.scheme.toLowerCase() != agentChatLinkScheme) {
    return null;
  }
  if (uri.host != 'v1' || uri.pathSegments.length != 1) return null;
  final chatId = uri.pathSegments.single;
  final workspaceId = uri.queryParameters['workspace'];
  if (chatId.isEmpty || workspaceId == null || workspaceId.isEmpty) {
    return null;
  }
  return AgentChatRef(chatId: chatId, workspaceId: workspaceId);
}

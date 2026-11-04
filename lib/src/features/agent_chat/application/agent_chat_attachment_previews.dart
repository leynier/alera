import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_attachment_previews.g.dart';

/// The bytes of attachment thumbnails read from their host, bounded to
/// [agentChatAttachmentCacheBytes] and kept for the app's life.
@Riverpod(keepAlive: true)
AgentChatAttachmentCache agentChatAttachmentCache(Ref ref) =>
    AgentChatAttachmentCache();

/// The cache key of [attachmentId] in [chatId] of [workspaceId].
String agentChatAttachmentCacheKey(
  String workspaceId,
  String chatId,
  String attachmentId,
) => '$workspaceId/$chatId/$attachmentId';

/// The host's copy of the uploaded image [attachmentId] for a thumbnail on
/// this machine (`agentChatAttachmentReadV1`), or null when the host cannot
/// serve it.
@riverpod
Future<AgentChatAttachmentBytes?> agentChatAttachmentPreview(
  Ref ref,
  String chatId,
  String workspaceId,
  String attachmentId,
) => fetchAgentChatAttachmentPreview(
  ref.watch(agentChatLifecycleRepositoryProvider),
  AgentChatRef(chatId: chatId, workspaceId: workspaceId),
  attachmentId: attachmentId,
  cache: ref.watch(agentChatAttachmentCacheProvider),
  key: agentChatAttachmentCacheKey(workspaceId, chatId, attachmentId),
);

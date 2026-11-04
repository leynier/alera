import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_attachment_previews.g.dart';

/// The bytes of attachment thumbnails read from their host, bounded to
/// [agentChatAttachmentCacheBytes] and kept for the app's life.
@Riverpod(keepAlive: true)
AgentChatAttachmentCache agentChatAttachmentCache(Ref ref) =>
    AgentChatAttachmentCache();

/// The cache key of [attachmentId] in [chatId] of [workspaceId] on [hostId].
String agentChatAttachmentCacheKey(
  String hostId,
  String workspaceId,
  String chatId,
  String attachmentId,
) => '$hostId/$workspaceId/$chatId/$attachmentId';

/// The host's copy of the uploaded image [attachmentId], read in pieces
/// through the relay (`agentChatAttachmentReadV1`), or null when the host
/// cannot serve it.
@riverpod
Future<AgentChatAttachmentBytes?> agentChatAttachmentPreview(
  Ref ref,
  String hostId,
  String workspaceId,
  String chatId,
  String attachmentId,
) async {
  final cache = ref.watch(agentChatAttachmentCacheProvider);
  final key = agentChatAttachmentCacheKey(
    hostId,
    workspaceId,
    chatId,
    attachmentId,
  );
  final cached = cache.peek(key);
  if (cached != null) return cached;
  final AgentChatLifecycleRepository repository;
  try {
    repository = (await ref.watch(agentChatRepositoryProvider(hostId).future))
        .lifecycle;
  } on Object {
    return null;
  }
  return fetchAgentChatAttachmentPreview(
    repository,
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    attachmentId: attachmentId,
    cache: cache,
    key: key,
  );
}

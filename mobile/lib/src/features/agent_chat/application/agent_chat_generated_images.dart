import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_generated_images.g.dart';

/// The image an `image_generation` item saved on the host
/// (`agentChatGeneratedImagesV1`), read in pieces through the relay. Kept a
/// minute after its last reader, so scrolling back does not read it again.
@riverpod
Future<AgentChatGeneratedImage> agentChatGeneratedImage(
  Ref ref,
  String hostId,
  String workspaceId,
  String chatId,
  String itemId,
) async {
  final link = ref.keepAlive();
  Timer? release;
  ref
    ..onCancel(() => release = Timer(const Duration(minutes: 1), link.close))
    ..onResume(() => release?.cancel())
    ..onDispose(() => release?.cancel());
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  return loadAgentChatGeneratedImage(
    repository.lifecycle,
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    itemId: itemId,
  );
}

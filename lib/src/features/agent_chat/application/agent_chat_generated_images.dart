import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_generated_images.g.dart';

/// The image an `image_generation` item saved on the host
/// (`agentChatGeneratedImagesV1`). Kept a minute after its last reader, so a
/// row scrolled away and back does not read it again.
@riverpod
Future<AgentChatGeneratedImage> agentChatGeneratedImage(
  Ref ref,
  String chatId,
  String workspaceId,
  String itemId,
) {
  final link = ref.keepAlive();
  Timer? release;
  ref
    ..onCancel(() => release = Timer(const Duration(minutes: 1), link.close))
    ..onResume(() => release?.cancel())
    ..onDispose(() => release?.cancel());
  return loadAgentChatGeneratedImage(
    ref.watch(agentChatLifecycleRepositoryProvider),
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    itemId: itemId,
  );
}

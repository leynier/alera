import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String agentChatRegenerateTitleLabel = 'Regenerate Title';
const String agentChatRegeneratingTitleLabel = 'Regenerating Title…';

/// Renames a chat. The chat header owns the title and writes the chat's
/// tab, so renaming a chat tab goes through the chat, not `tab.rename`.
Future<void> renameAgentChat(
  WidgetRef ref,
  AgentChatRef chat,
  String title,
) async {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return;
  await ref
      .read(agentChatRepositoryProvider)
      .rename(
        chat,
        requestId: ref.read(agentChatIdGeneratorProvider)(),
        title: trimmed,
      );
}

/// A person asked for a new AI title (`agentChatTitleGenerationV1`), so it
/// may replace a title they chose. The job runs on the host; the chat's
/// `titleGeneration` reports it.
Future<void> regenerateAgentChatTitle(WidgetRef ref, AgentChatRef chat) => ref
    .read(agentChatLifecycleRepositoryProvider)
    .regenerateTitle(
      chat,
      requestId: ref.read(agentChatIdGeneratorProvider)(),
      replaceUserTitle: true,
    );

/// Whether the runtime offers AI chat titles; false when it cannot say.
Future<bool> agentChatTitleGenerationAvailable(WidgetRef ref) async {
  try {
    return await ref.read(
      agentChatCapabilityProvider(AgentChatWire.titleGenerationCapability)
          .future,
    );
  } on Object {
    return false;
  }
}

/// Whether the loaded chat shows a title job running. A chat nobody has
/// open reports false; the host refuses nothing for it.
bool agentChatTitleGenerating(WidgetRef ref, AgentChatRef chat) {
  final provider = agentChatControllerProvider(chat.chatId, chat.workspaceId);
  return ref.exists(provider) &&
      ref.read(provider).thread?.titleGeneration?.generating == true;
}

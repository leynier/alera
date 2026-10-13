import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/infra/runtime_host_agent_chat_transport.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'agent_chat_providers.g.dart';

@Riverpod(keepAlive: true)
AgentChatRepository agentChatRepository(Ref ref) => RuntimeAgentChatRepository(
  RuntimeHostAgentChatTransport(ref.watch(runtimeHostClientProvider)),
);

/// Whether the connected runtime runs agent chats. An unreachable runtime
/// reads as unsupported so no entry point is offered that would fail.
@riverpod
Future<bool> agentChatSupported(Ref ref) async {
  try {
    return await ref.watch(agentChatRepositoryProvider).supported();
  } on Object {
    return false;
  }
}

/// Provider instances a workspace's runtime can start chats with.
@riverpod
Future<List<AgentChatProviderInstance>> agentChatProviderCatalog(
  Ref ref,
  String workspaceId,
) => ref.watch(agentChatRepositoryProvider).providers(workspaceId: workspaceId);

/// Allocates request and client message ids; tests pin it.
@Riverpod(keepAlive: true)
String Function() agentChatIdGenerator(Ref ref) =>
    () => const Uuid().v4();

/// The clock optimistic messages and live turn timers read; tests pin it.
@Riverpod(keepAlive: true)
DateTime Function() agentChatClock(Ref ref) => DateTime.now;

/// Unsent composer text and attachments per chat. Kept for the session so a
/// tab switch or a reconnect never loses a draft.
@Riverpod(keepAlive: true)
AgentChatComposerDrafts agentChatComposerDrafts(Ref ref) =>
    AgentChatComposerDrafts();

/// The provider instance the last new chat started with, offered first the
/// next time in this session.
@Riverpod(keepAlive: true)
class AgentChatLaunchPreference extends _$AgentChatLaunchPreference {
  @override
  String? build() => null;

  void remember(String providerInstanceId) => state = providerInstanceId;
}

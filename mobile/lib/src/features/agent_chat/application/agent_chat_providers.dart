import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/mobile_agent_chat_transport.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_providers.g.dart';

/// The paired runtime as agent chats see it: the same connection the
/// workspace screens use, so it rebuilds with every reconnect, which is what
/// makes each open chat reload its snapshot.
@riverpod
Future<MobileAgentChatClient> mobileAgentChatClient(
  Ref ref,
  String hostId,
) async {
  final Object client = await ref.watch(workspaceClientProvider(hostId).future);
  if (client is MobileAgentChatClient) return client;
  throw const AgentChatUpdateRequired();
}

@riverpod
Future<AgentChatRepository> agentChatRepository(Ref ref, String hostId) async =>
    RuntimeAgentChatRepository(
      MobileAgentChatTransport(
        await ref.watch(mobileAgentChatClientProvider(hostId).future),
      ),
    );

/// Whether the paired runtime serves agent chats; New Chat is offered only
/// when it does. An older runtime, or a client without the surface, is a
/// plain no rather than an error.
@riverpod
Future<bool> agentChatSupported(Ref ref, String hostId) async {
  final Object client = await ref.watch(workspaceClientProvider(hostId).future);
  return client is MobileAgentChatClient &&
      client.runtimeCapabilities.contains(AgentChatWire.capability);
}

/// Chats of [workspaceId] that were closed; their history stays on the host
/// and Reopen brings one back in a new tab.
@riverpod
Future<List<AgentChatSummary>> agentChatArchivedChats(
  Ref ref,
  String hostId,
  String workspaceId,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  final chats = await repository.list(
    workspaceId: workspaceId,
    includeArchived: true,
  );
  return <AgentChatSummary>[
    for (final chat in chats)
      if (chat.archived) chat,
  ];
}

/// Providers the runtime can start a chat with in [workspaceId], with the
/// availability it verified on that host.
@riverpod
Future<List<AgentChatProviderInstance>> agentChatProviders(
  Ref ref,
  String hostId,
  String workspaceId,
) async =>
    (await ref.watch(agentChatRepositoryProvider(hostId).future))
        .providers(workspaceId: workspaceId);

import 'dart:async';

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

/// Whether the paired runtime advertises [capability]. Every additive chat
/// control asks here first, so an older runtime keeps its older behavior.
@riverpod
Future<bool> agentChatCapability(
  Ref ref,
  String hostId,
  String capability,
) async {
  // The chat client is the connection every chat verb goes through, so its
  // capabilities are the ones those verbs are answered against.
  try {
    final client = await ref.watch(
      mobileAgentChatClientProvider(hostId).future,
    );
    return client.runtimeCapabilities.contains(capability);
  } on Object {
    return false;
  }
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
  _refreshOnListChange(ref, repository);
  final chats = await repository.list(
    workspaceId: workspaceId,
    includeArchived: true,
  );
  return <AgentChatSummary>[
    for (final chat in chats)
      if (chat.archived) chat,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

/// Providers the runtime can start a chat with in [workspaceId], with the
/// availability it verified on that host. Refreshed when the host reports a
/// provider change, so an open picker follows a Settings edit made anywhere.
@riverpod
Future<List<AgentChatProviderInstance>> agentChatProviders(
  Ref ref,
  String hostId,
  String workspaceId,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  _refreshOn(ref, repository.settings.watchProviders());
  return repository.providers(workspaceId: workspaceId);
}

/// The chat preferences of one runtime: defaults for new chats and model
/// visibility. [remoteHostId] names a Remote Host behind the paired runtime,
/// whose chats follow its own preferences; null is the paired runtime.
/// Absent on a runtime without them, where defaults resolve from the catalog
/// alone and every model is shown.
@riverpod
Future<AgentChatPreferences?> agentChatPreferences(
  Ref ref,
  String hostId,
  String? remoteHostId,
) async {
  final repository = await ref.watch(
    agentChatRepositoryProvider(hostId).future,
  );
  final settings = repository.settings;
  if (!await settings.preferencesSupported()) return null;
  _refreshOn(
    ref,
    settings.watchPreferences().where(
      (change) => change.hostId == null || change.hostId == remoteHostId,
    ),
  );
  return settings.preferences(hostId: remoteHostId);
}

void _refreshOn(Ref ref, Stream<Object?> changes) {
  final subscription = changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
}

void _refreshOnListChange(Ref ref, AgentChatRepository repository) {
  final subscription = repository.watchList().listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(subscription.cancel);
}

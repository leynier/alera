import 'dart:async';

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

/// Preferences and provider settings of the connected runtime. Repositories
/// without them (older runtimes, test fakes) answer as unsupported.
@Riverpod(keepAlive: true)
AgentChatSettingsRepository agentChatSettingsRepository(Ref ref) =>
    ref.watch(agentChatRepositoryProvider).settings;

/// Chat controls that only newer runtimes offer, such as editing a queued
/// message or steering it into the running turn.
@Riverpod(keepAlive: true)
AgentChatLifecycleRepository agentChatLifecycleRepository(Ref ref) =>
    ref.watch(agentChatRepositoryProvider).lifecycle;

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

/// Whether the runtime advertises one of the additive `AgentChatWire`
/// capabilities. A failed check reads as unsupported.
@riverpod
Future<bool> agentChatCapability(Ref ref, String capability) async {
  try {
    return await ref
        .watch(agentChatLifecycleRepositoryProvider)
        .supports(capability);
  } on Object {
    return false;
  }
}

/// This Device is keyed as `null` so desktop keeps one preferences cache for
/// it whichever spelling a caller has.
String? agentChatHostKey(String? hostId) {
  final trimmed = hostId?.trim();
  return trimmed == null || trimmed.isEmpty || trimmed == 'local'
      ? null
      : trimmed;
}

/// Provider instances a workspace's runtime can start chats with. A provider
/// settings change on the runtime reads the catalog again.
@riverpod
Future<List<AgentChatProviderInstance>> agentChatProviderCatalog(
  Ref ref,
  String workspaceId,
) {
  final subscription = ref
      .watch(agentChatSettingsRepositoryProvider)
      .watchProviders()
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(subscription.cancel()));
  return ref
      .watch(agentChatRepositoryProvider)
      .providers(workspaceId: workspaceId);
}

/// The runtime's chat preferences for [hostId] (see [agentChatHostKey]).
/// Empty preferences when the runtime does not keep them; Settings checks
/// [AgentChatSettingsRepository.preferencesSupported] on its own.
@riverpod
Future<AgentChatPreferences> agentChatPreferences(
  Ref ref,
  String? hostId,
) async {
  final repository = ref.watch(agentChatSettingsRepositoryProvider);
  final subscription = repository.watchPreferences().listen((event) {
    if (event.hostId == null || agentChatHostKey(event.hostId) == hostId) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  try {
    if (!await repository.preferencesSupported()) {
      return const AgentChatPreferences();
    }
    return await repository.preferences(hostId: hostId);
  } on AgentChatCapabilityRequired {
    return const AgentChatPreferences();
  } on UnsupportedError {
    return const AgentChatPreferences();
  }
}

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

/// The selection of the last chat that sent its first message in this
/// session. Runtimes with chat preferences remember it themselves; this only
/// stands in for runtimes that do not.
@Riverpod(keepAlive: true)
class AgentChatLaunchPreference extends _$AgentChatLaunchPreference {
  @override
  AgentChatSelection? build() => null;

  void remember(AgentChatSelection selection) => state = selection;
}

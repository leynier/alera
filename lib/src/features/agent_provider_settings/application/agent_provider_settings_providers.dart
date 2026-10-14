import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_failure.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_writer.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_provider_settings_providers.g.dart';

/// Runtime capability for running a provider setup terminal on a Remote Host.
const String agentProviderRemoteSetupCapability =
    'agentChatRemoteProviderSetupV1';

/// Which provider settings features the connected runtime offers. All are
/// read from the local runtime: a Remote Host is reached through it.
class const AgentProviderSettingsSupport({
  final bool providerSettings = false,
  final bool preferences = false,

  /// Whether setup terminals can run on a Remote Host. This Device always can.
  final bool remoteSetup = false,
});

@riverpod
Future<AgentProviderSettingsSupport> agentProviderSettingsSupport(
  Ref ref,
) async {
  final repository = ref.watch(agentChatSettingsRepositoryProvider);
  // An unreachable runtime reads as unsupported; the catalog request reports
  // the connection problem itself.
  Future<bool> check(Future<bool> Function() supported) async {
    try {
      return await supported();
    } on Object {
      return false;
    }
  }

  final lifecycle = ref.watch(agentChatLifecycleRepositoryProvider);
  final results = await Future.wait(<Future<bool>>[
    check(repository.providerSettingsSupported),
    check(repository.preferencesSupported),
    check(() => lifecycle.supports(agentProviderRemoteSetupCapability)),
  ]);
  return AgentProviderSettingsSupport(
    providerSettings: results[0],
    preferences: results[1],
    remoteSetup: results[2],
  );
}

/// Whether a settings event for [eventHostId] concerns [hostId]. An event
/// without a host is a wildcard, so every host view reloads.
bool agentProviderEventConcerns(String? eventHostId, String? hostId) {
  if (eventHostId == null || eventHostId.trim().isEmpty) {
    return true;
  }
  return normalizedRemoteHostId(eventHostId) == normalizedRemoteHostId(hostId);
}

class const AgentProviderCatalogState({
  required final List<AgentChatProviderInstance> rows,
  final bool checking = false,
  final String? refreshError,
});

/// The provider catalog of one host, as Settings shows it. [hostId] is null
/// for This Device. Reads come from the host's status cache; [refresh] forces
/// a re-check.
@riverpod
class AgentProviderCatalogController extends _$AgentProviderCatalogController {
  @override
  Future<AgentProviderCatalogState> build(String? hostId) async {
    final repository = ref.watch(agentChatSettingsRepositoryProvider);
    final subscription = repository.watchProviders().listen((event) {
      if (agentProviderEventConcerns(event.hostId, hostId)) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    final rows = await repository.providers(hostId: hostId);
    return AgentProviderCatalogState(rows: rows);
  }

  Future<void> refresh() async {
    final previous = state.value?.rows ?? const <AgentChatProviderInstance>[];
    state = AsyncData(
      AgentProviderCatalogState(rows: previous, checking: true),
    );
    try {
      final rows = await ref
          .read(agentChatSettingsRepositoryProvider)
          .providers(hostId: hostId, refresh: true);
      if (ref.mounted) {
        state = AsyncData(AgentProviderCatalogState(rows: rows));
      }
    } on Object catch (error) {
      if (ref.mounted) {
        state = AsyncData(
          AgentProviderCatalogState(
            rows: previous,
            refreshError: AgentProviderSettingsFailure.from(error).message,
          ),
        );
      }
    }
  }
}

/// The stored provider instances of one host and the writes against them.
@riverpod
class AgentProviderSettingsController
    extends _$AgentProviderSettingsController {
  @override
  Future<AgentChatProviderSettingsSnapshot> build(String? hostId) async {
    final repository = ref.watch(agentChatSettingsRepositoryProvider);
    final subscription = repository.watchProviders().listen((event) {
      final known = state.value?.revision;
      if (agentProviderEventConcerns(event.hostId, hostId) &&
          (event.revision == null || event.revision != known)) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    return repository.providerInstances(hostId: hostId);
  }

  AgentProviderSettingsWriter get _writer => AgentProviderSettingsWriter(
    repository: ref.read(agentChatSettingsRepositoryProvider),
    newRequestId: ref.read(agentChatIdGeneratorProvider),
    hostId: hostId,
  );

  int get _revision => state.value?.revision ?? 0;

  Future<void> save({
    required AgentProviderInstanceDraft draft,
    required AgentProviderInstanceDraft? saved,
    List<AgentProviderPendingSecret> secrets =
        const <AgentProviderPendingSecret>[],
  }) => _apply(
    () => _writer.save(
      revision: _revision,
      draft: draft,
      saved: saved,
      secrets: secrets,
      onProgress: _publish,
    ),
  );

  Future<void> setEnabled({
    required String providerInstanceId,
    required String provider,
    required bool enabled,
  }) => _apply(
    () => _writer.setEnabled(
      revision: _revision,
      providerInstanceId: providerInstanceId,
      provider: provider,
      enabled: enabled,
    ),
  );

  Future<AgentChatProviderRemovalImpact> removalImpact(
    String providerInstanceId,
  ) => _writer.removalImpact(providerInstanceId);

  Future<void> remove(String providerInstanceId, {bool allowInUse = false}) =>
      _apply(
        () => _writer.remove(
          revision: _revision,
          providerInstanceId: providerInstanceId,
          allowInUse: allowInUse,
        ),
      );

  Future<void> _apply(
    Future<AgentChatProviderSettingsSnapshot> Function() write,
  ) async {
    try {
      _publish(await write());
    } on AgentProviderSettingsFailure catch (failure) {
      if (failure.kind == .revisionConflict && ref.mounted) {
        ref.invalidateSelf();
      }
      rethrow;
    } finally {
      // The catalog reflects enable state and models; reload it even when
      // the host's change event has not arrived yet.
      if (ref.mounted) {
        ref.invalidate(agentProviderCatalogControllerProvider(hostId));
      }
    }
  }

  void _publish(AgentChatProviderSettingsSnapshot snapshot) {
    if (ref.mounted) {
      state = AsyncData(snapshot);
    }
  }
}

@riverpod
AgentProviderPreferencesWriter agentProviderPreferencesWriter(
  Ref ref,
  String? hostId,
) => AgentProviderPreferencesWriter(
  repository: ref.watch(agentChatSettingsRepositoryProvider),
  newRequestId: ref.watch(agentChatIdGeneratorProvider),
  hostId: hostId,
);

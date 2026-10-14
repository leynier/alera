import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'agent_provider_settings_providers.g.dart';

const Uuid _uuid = Uuid();

/// The paired runtime's settings service for chat agents.
@riverpod
Future<AgentChatSettingsRepository> agentProviderSettingsRepository(
  Ref ref,
  String hostId,
) async =>
    (await ref.watch(agentChatRepositoryProvider(hostId).future)).settings;

/// Every agent instance on one host with the status the host last verified.
/// [remoteHostId] is a Remote Host behind the paired runtime; null is the
/// paired runtime itself. The answer comes from the host's status cache, so
/// opening this does not probe providers; Refresh does.
@riverpod
Future<List<AgentChatProviderInstance>> agentProviderCatalog(
  Ref ref,
  String hostId,
  String? remoteHostId,
) async {
  final settings = await ref.watch(
    agentProviderSettingsRepositoryProvider(hostId).future,
  );
  final changes = settings
      .watchProviders()
      .where((change) => change.hostId == null || change.hostId == remoteHostId)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  return settings.providers(hostId: remoteHostId);
}

/// The host's stored instance settings, or null on a runtime that keeps
/// none, where the screen stays read-only.
@riverpod
Future<AgentChatProviderSettingsSnapshot?> agentProviderInstances(
  Ref ref,
  String hostId,
  String? remoteHostId,
) async {
  final settings = await ref.watch(
    agentProviderSettingsRepositoryProvider(hostId).future,
  );
  if (!await settings.providerSettingsSupported()) return null;
  final changes = settings
      .watchProviders()
      .where((change) => change.hostId == null || change.hostId == remoteHostId)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  return settings.providerInstances(hostId: remoteHostId);
}

/// The edits a paired phone may make: turning an instance on or off, its
/// default and custom models, write-only secrets, and the host's chat
/// preferences. Launch definitions stay with the desktop. Each write names
/// the revision it was made against, so an edit made elsewhere in between is
/// refused instead of overwritten.
class AgentProviderSettingsActions(
  final AgentChatSettingsRepository _settings,
  final String? _remoteHostId,
) {
  Future<AgentChatProviderSettingsSnapshot> setEnabled(
    AgentChatProviderSettingsSnapshot snapshot,
    String instanceId, {
    required bool enabled,
  }) => _upsert(
    snapshot,
    AgentChatProviderInstanceEdit(
      providerInstanceId: instanceId,
      enabled: enabled,
    ),
  );

  Future<AgentChatProviderSettingsSnapshot> setDefaultModel(
    AgentChatProviderSettingsSnapshot snapshot,
    String instanceId,
    String? model,
  ) => _upsert(
    snapshot,
    AgentChatProviderInstanceEdit(
      providerInstanceId: instanceId,
      defaultModel: model,
      resetDefaultModel: model == null,
    ),
  );

  Future<AgentChatProviderSettingsSnapshot> setCustomModels(
    AgentChatProviderSettingsSnapshot snapshot,
    String instanceId,
    List<String> models,
  ) => _upsert(
    snapshot,
    AgentChatProviderInstanceEdit(
      providerInstanceId: instanceId,
      customModels: List.unmodifiableOf(models),
    ),
  );

  Future<AgentChatProviderSettingsSnapshot> setSecret(
    AgentChatProviderSettingsSnapshot snapshot,
    String instanceId,
    String name,
    String value,
  ) => _settings.setProviderSecret(
    requestId: _uuid.v4(),
    expectedRevision: snapshot.revision,
    providerInstanceId: instanceId,
    name: name,
    value: value,
    hostId: _remoteHostId,
  );

  Future<AgentChatProviderSettingsSnapshot> clearSecret(
    AgentChatProviderSettingsSnapshot snapshot,
    String instanceId,
    String name,
  ) => _settings.clearProviderSecret(
    requestId: _uuid.v4(),
    expectedRevision: snapshot.revision,
    providerInstanceId: instanceId,
    name: name,
    hostId: _remoteHostId,
  );

  /// Asks the host to check every provider again now, past its cache.
  Future<List<AgentChatProviderInstance>> refresh() =>
      _settings.providers(hostId: _remoteHostId, refresh: true);

  Future<AgentChatPreferences> setDefaultSelection(
    AgentChatPreferences preferences,
    AgentChatSelection? selection,
  ) => _preferences(preferences, <AgentChatPreferenceOperation>[
    AgentChatSetDefaultSelection(selection),
  ]);

  Future<AgentChatPreferences> setProjectDefault(
    AgentChatPreferences preferences,
    String projectId,
    AgentChatSelection? selection,
  ) => _preferences(preferences, <AgentChatPreferenceOperation>[
    AgentChatSetProjectDefault(projectId: projectId, selection: selection),
  ]);

  Future<AgentChatPreferences> setModelPreferences(
    AgentChatPreferences preferences,
    String instanceId,
    AgentChatModelPreferences models,
  ) => _preferences(preferences, <AgentChatPreferenceOperation>[
    AgentChatSetModelPreferences(
      providerInstanceId: instanceId,
      preferences: models,
    ),
  ]);

  Future<AgentChatProviderSettingsSnapshot> _upsert(
    AgentChatProviderSettingsSnapshot snapshot,
    AgentChatProviderInstanceEdit edit,
  ) => _settings.upsertProviderInstance(
    requestId: _uuid.v4(),
    expectedRevision: snapshot.revision,
    instance: edit,
    hostId: _remoteHostId,
  );

  Future<AgentChatPreferences> _preferences(
    AgentChatPreferences preferences,
    List<AgentChatPreferenceOperation> operations,
  ) => _settings.updatePreferences(
    AgentChatPreferencesUpdate(
      requestId: _uuid.v4(),
      expectedRevision: preferences.revision,
      operations: operations,
    ),
    hostId: _remoteHostId,
  );
}

/// Whether a failed settings write lost a race with another device, which
/// the screen answers by showing the latest values rather than an error.
bool agentProviderSettingsConflict(Object error) =>
    error is AgentChatRequestException &&
    error.code == AgentChatErrorCodes.revisionConflict;

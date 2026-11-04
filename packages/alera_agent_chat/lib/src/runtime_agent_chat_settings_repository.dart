import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_preference_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_preferences.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_settings.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_settings_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

final class RuntimeAgentChatSettingsRepository
    extends AgentChatSettingsRepository {
  const RuntimeAgentChatSettingsRepository(this._transport);

  final AgentChatTransport _transport;

  Future<AgentChatJson> _request(
    String capability,
    String verb,
    AgentChatJson payload,
  ) async {
    if (!await _transport.supportsCapability(capability)) {
      throw AgentChatCapabilityRequired(capability);
    }
    return _transport.request(verb, payload);
  }

  @override
  Future<bool> preferencesSupported() =>
      _transport.supportsCapability(AgentChatWire.preferencesCapability);

  @override
  Future<bool> providerSettingsSupported() =>
      _transport.supportsCapability(AgentChatWire.providerSettingsCapability);

  @override
  Future<List<AgentChatProviderInstance>> providers({
    String? workspaceId,
    String? hostId,
    bool refreshModels = false,
    bool refresh = false,
  }) async => agentChatProvidersFromJson(
    await _request(
      AgentChatWire.capability,
      AgentChatWire.providers,
      <String, Object?>{
        'workspaceId': ?workspaceId,
        'hostId': ?hostId,
        if (refreshModels) 'refreshModels': true,
        if (refresh) 'refresh': true,
      },
    ),
  );

  @override
  Future<AgentChatPreferences> preferences({String? hostId}) async =>
      AgentChatPreferences.fromJson(
        await _request(
          AgentChatWire.preferencesCapability,
          AgentChatWire.preferencesGet,
          <String, Object?>{'hostId': ?hostId},
        ),
      );

  @override
  Future<AgentChatPreferences> updatePreferences(
    AgentChatPreferencesUpdate input, {
    String? hostId,
  }) async => AgentChatPreferences.fromJson(
    await _request(
      AgentChatWire.preferencesCapability,
      AgentChatWire.preferencesUpdate,
      <String, Object?>{'hostId': ?hostId, ...input.toJson()},
    ),
  );

  Stream<AgentChatSettingsChanged> _watch(String eventName) => _transport.events
      .where(
        (event) =>
            event.name == eventName ||
            event.name == AgentChatTransportEvents.connected,
      )
      .map(
        (event) => AgentChatSettingsChanged(
          hostId: agentChatJsonString(event.payload['hostId']),
          revision: agentChatJsonInt(event.payload['revision']),
        ),
      );

  @override
  Stream<AgentChatSettingsChanged> watchPreferences() =>
      _watch(AgentChatWire.preferencesChangedEvent);

  @override
  Stream<AgentChatSettingsChanged> watchProviders() =>
      _watch(AgentChatWire.providersChangedEvent);

  Future<AgentChatProviderSettingsSnapshot> _settings(
    String verb,
    AgentChatJson payload,
  ) async => AgentChatProviderSettingsSnapshot.fromJson(
    await _request(AgentChatWire.providerSettingsCapability, verb, payload),
  );

  @override
  Future<AgentChatProviderSettingsSnapshot> providerInstances({
    String? hostId,
  }) => _settings(AgentChatWire.providerInstancesGet, <String, Object?>{
    'hostId': ?hostId,
  });

  @override
  Future<AgentChatProviderSettingsSnapshot> upsertProviderInstance({
    required String requestId,
    required int expectedRevision,
    required AgentChatProviderInstanceEdit instance,
    String? hostId,
  }) => _settings(AgentChatWire.providerInstancesUpsert, <String, Object?>{
    'hostId': ?hostId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'instance': instance.toJson(),
  });

  @override
  Future<AgentChatProviderSettingsSnapshot> removeProviderInstance({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    bool allowInUse = false,
    String? hostId,
  }) => _settings(AgentChatWire.providerInstancesRemove, <String, Object?>{
    'hostId': ?hostId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'providerInstanceId': providerInstanceId,
    if (allowInUse) 'allowInUse': true,
  });

  @override
  Future<AgentChatProviderRemovalImpact> providerRemovalImpact({
    required String providerInstanceId,
    String? hostId,
  }) async => AgentChatProviderRemovalImpact.fromJson(
    await _request(
      AgentChatWire.providerSettingsCapability,
      AgentChatWire.providerInstancesRemovalImpact,
      <String, Object?>{
        'hostId': ?hostId,
        'providerInstanceId': providerInstanceId,
      },
    ),
  );

  @override
  Future<AgentChatProviderSettingsSnapshot> setProviderSecret({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    required String name,
    required String value,
    String? hostId,
  }) => _settings(AgentChatWire.secretsSet, <String, Object?>{
    'hostId': ?hostId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'providerInstanceId': providerInstanceId,
    'name': name,
    'value': value,
  });

  @override
  Future<AgentChatProviderSettingsSnapshot> clearProviderSecret({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    required String name,
    String? hostId,
  }) => _settings(AgentChatWire.secretsClear, <String, Object?>{
    'hostId': ?hostId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'providerInstanceId': providerInstanceId,
    'name': name,
  });
}

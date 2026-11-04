import 'package:alera_agent_chat/src/agent_chat_preference_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_preferences.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_settings.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';

class const AgentChatSettingsChanged({
  final String? hostId,
  final int? revision,
});

/// Additive service: older repository fakes need no new implementations.
/// Callers feature-detect support before presenting the corresponding controls.
abstract class AgentChatSettingsRepository {
  const AgentChatSettingsRepository();

  Future<bool> preferencesSupported() async => false;
  Future<bool> providerSettingsSupported() async => false;

  Future<List<AgentChatProviderInstance>> providers({
    String? workspaceId,
    String? hostId,
    bool refreshModels = false,
    bool refresh = false,
  }) => Future.error(UnsupportedError('Provider catalog is unavailable.'));

  Future<AgentChatPreferences> preferences({String? hostId}) =>
      Future.error(UnsupportedError('Chat preferences are unavailable.'));

  Future<AgentChatPreferences> updatePreferences(
    AgentChatPreferencesUpdate input, {
    String? hostId,
  }) => Future.error(UnsupportedError('Chat preferences are unavailable.'));

  Stream<AgentChatSettingsChanged> watchPreferences() => const Stream.empty();
  Stream<AgentChatSettingsChanged> watchProviders() => const Stream.empty();

  Future<AgentChatProviderSettingsSnapshot> providerInstances({
    String? hostId,
  }) => Future.error(UnsupportedError('Provider settings are unavailable.'));

  Future<AgentChatProviderSettingsSnapshot> upsertProviderInstance({
    required String requestId,
    required int expectedRevision,
    required AgentChatProviderInstanceEdit instance,
    String? hostId,
  }) => Future.error(UnsupportedError('Provider settings are unavailable.'));

  Future<AgentChatProviderSettingsSnapshot> removeProviderInstance({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    bool allowInUse = false,
    String? hostId,
  }) => Future.error(UnsupportedError('Provider settings are unavailable.'));

  Future<AgentChatProviderRemovalImpact> providerRemovalImpact({
    required String providerInstanceId,
    String? hostId,
  }) => Future.error(UnsupportedError('Provider settings are unavailable.'));

  Future<AgentChatProviderSettingsSnapshot> setProviderSecret({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    required String name,
    required String value,
    String? hostId,
  }) => Future.error(UnsupportedError('Provider secrets are unavailable.'));

  Future<AgentChatProviderSettingsSnapshot> clearProviderSecret({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    required String name,
    String? hostId,
  }) => Future.error(UnsupportedError('Provider secrets are unavailable.'));
}

final class UnsupportedAgentChatSettingsRepository
    extends AgentChatSettingsRepository {
  const UnsupportedAgentChatSettingsRepository();
}

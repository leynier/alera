import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';

/// In-memory provider settings and preferences of one runtime. Every write
/// is logged in [calls] as `verb id @expectedRevision requestId host=...` and
/// advances [revision] by one, like the host's domain revision.
class FakeAgentChatSettingsRepository extends AgentChatSettingsRepository {
  FakeAgentChatSettingsRepository({
    this.revision = 0,
    this.providerSettings = true,
    this.preferencesEnabled = true,
    List<AgentChatProviderInstance>? catalog,
    List<AgentChatProviderInstanceEnvelope>? instances,
    this.preferencesValue = const AgentChatPreferences(),
  }) : catalog = catalog ?? <AgentChatProviderInstance>[],
       instances = instances ?? <AgentChatProviderInstanceEnvelope>[];

  int revision;
  bool providerSettings;
  bool preferencesEnabled;
  List<AgentChatProviderInstance> catalog;
  List<AgentChatProviderInstanceEnvelope> instances;
  AgentChatPreferences preferencesValue;
  AgentChatProviderRemovalImpact? impact;

  final List<String> calls = <String>[];
  final List<AgentChatProviderInstanceEdit> upserts =
      <AgentChatProviderInstanceEdit>[];
  final List<String> secretValues = <String>[];
  final List<AgentChatPreferencesUpdate> preferenceUpdates =
      <AgentChatPreferencesUpdate>[];
  final List<({String? hostId, bool refresh})> catalogReads =
      <({String? hostId, bool refresh})>[];

  /// Thrown by the next settings write or impact read, then cleared.
  Object? nextError;
  Object? nextPreferencesError;

  /// The next write fails as a dropped connection once, then succeeds.
  bool dropNextConnection = false;

  final StreamController<AgentChatSettingsChanged> providersChanged =
      StreamController<AgentChatSettingsChanged>.broadcast();
  final StreamController<AgentChatSettingsChanged> preferencesChanged =
      StreamController<AgentChatSettingsChanged>.broadcast();

  String _host(String? hostId) => 'host=${hostId ?? 'local'}';

  AgentChatProviderSettingsSnapshot _write(String call) {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    calls.add(call);
    if (dropNextConnection) {
      dropNextConnection = false;
      throw const AgentChatConnectionException('connection closed');
    }
    revision += 1;
    return AgentChatProviderSettingsSnapshot(
      instances: List<AgentChatProviderInstanceEnvelope>.of(instances),
      revision: revision,
    );
  }

  @override
  Future<bool> providerSettingsSupported() async => providerSettings;

  @override
  Future<bool> preferencesSupported() async => preferencesEnabled;

  @override
  Future<List<AgentChatProviderInstance>> providers({
    String? workspaceId,
    String? hostId,
    bool refreshModels = false,
    bool refresh = false,
  }) async {
    catalogReads.add((hostId: hostId, refresh: refresh));
    return List<AgentChatProviderInstance>.of(catalog);
  }

  @override
  Stream<AgentChatSettingsChanged> watchProviders() => providersChanged.stream;

  @override
  Stream<AgentChatSettingsChanged> watchPreferences() =>
      preferencesChanged.stream;

  @override
  Future<AgentChatProviderSettingsSnapshot> providerInstances({
    String? hostId,
  }) async => AgentChatProviderSettingsSnapshot(
    instances: List<AgentChatProviderInstanceEnvelope>.of(instances),
    revision: revision,
  );

  @override
  Future<AgentChatProviderSettingsSnapshot> upsertProviderInstance({
    required String requestId,
    required int expectedRevision,
    required AgentChatProviderInstanceEdit instance,
    String? hostId,
  }) async {
    final snapshot = _write(
      'upsert ${instance.providerInstanceId} @$expectedRevision $requestId '
      '${_host(hostId)}',
    );
    upserts.add(instance);
    return snapshot;
  }

  @override
  Future<AgentChatProviderSettingsSnapshot> removeProviderInstance({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    bool allowInUse = false,
    String? hostId,
  }) async => _write(
    'remove $providerInstanceId @$expectedRevision $requestId '
    'allowInUse=$allowInUse ${_host(hostId)}',
  );

  @override
  Future<AgentChatProviderRemovalImpact> providerRemovalImpact({
    required String providerInstanceId,
    String? hostId,
  }) async {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return impact ??
        AgentChatProviderRemovalImpact(providerInstanceId: providerInstanceId);
  }

  @override
  Future<AgentChatProviderSettingsSnapshot> setProviderSecret({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    required String name,
    required String value,
    String? hostId,
  }) async {
    final snapshot = _write(
      'secret.set $providerInstanceId $name @$expectedRevision $requestId '
      '${_host(hostId)}',
    );
    secretValues.add(value);
    return snapshot;
  }

  @override
  Future<AgentChatProviderSettingsSnapshot> clearProviderSecret({
    required String requestId,
    required int expectedRevision,
    required String providerInstanceId,
    required String name,
    String? hostId,
  }) async => _write(
    'secret.clear $providerInstanceId $name @$expectedRevision $requestId '
    '${_host(hostId)}',
  );

  @override
  Future<AgentChatPreferences> preferences({String? hostId}) async =>
      preferencesValue;

  @override
  Future<AgentChatPreferences> updatePreferences(
    AgentChatPreferencesUpdate input, {
    String? hostId,
  }) async {
    preferenceUpdates.add(input);
    final error = nextPreferencesError;
    if (error != null) {
      nextPreferencesError = null;
      throw error;
    }
    return preferencesValue;
  }

  Future<void> dispose() async {
    await providersChanged.close();
    await preferencesChanged.close();
  }
}

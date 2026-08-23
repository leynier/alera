import 'dart:async';

import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_removal_impact.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

class RuntimeAgentProfileRepository {
  RuntimeAgentProfileRepository(
    this._client, {
    this.beforeAccess,
    RuntimeChangeCoalescer? coalescer,
  }) : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;
  final RuntimeChangeCoalescer _coalescer;

  Future<List<AgentProfile>> list() async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest('agentProfile.list');
    return _profileListFromPayload(payload);
  }

  Stream<List<AgentProfile>> watchAll() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'agentProfilesChanged'},
      readSnapshot: list,
      coalesceKey: 'agentProfiles',
      coalescer: _coalescer,
    );
  }

  /// Creates a profile when [id] is null and updates it otherwise. The host
  /// mints the id so the app never has to invent one.
  Future<AgentProfile> upsert({
    String? id,
    int? expectedRevision,
    required String name,
    required String agentType,
    required AgentProfileLaunchMode launchMode,
    String command = '',
    Map<String, Object?> managedConfig = const <String, Object?>{},
    String customPrompt = '',
    String description = '',
    String? quotaGroup,
  }) async {
    await beforeAccess?.call();
    final requiredCapabilities = <String, String>{};
    if (id != null) {
      if (expectedRevision == null) {
        throw ArgumentError.notNull('expectedRevision');
      }
      requiredCapabilities[aleraRuntimeHostAgentProfileRevisionsCapability] =
          'Safe agent profile editing requires a newer runtime host. Restart '
          'Alera to replace the running host.';
    }
    if (launchMode == AgentProfileLaunchMode.managed) {
      requiredCapabilities[aleraRuntimeHostManagedAgentProfilesCapability] =
          'Managed agent profiles require a newer runtime host. Restart Alera '
          'to replace the running host, or use Command mode.';
    }
    final payload = await _mutationRequest(
      'agentProfile.upsert',
      <String, Object?>{
        'id': ?id,
        'expectedRevision': ?expectedRevision,
        'name': name,
        'agentType': agentType,
        'command': launchMode == AgentProfileLaunchMode.command ? command : '',
        'launchMode': launchMode.name,
        if (launchMode == AgentProfileLaunchMode.managed)
          'managedConfig': managedConfig,
        'customPrompt': customPrompt,
        'description': description,
        'quotaGroup': quotaGroup,
      },
      requiredCapabilities,
    );
    return AgentProfile.fromJson(_mapFromPayload(payload));
  }

  Future<List<AgentProfile>> reorder(
    List<String> profileIds, {
    required Map<String, int> expectedRevisions,
  }) async {
    await beforeAccess?.call();
    final payload = await _mutationRequest(
      'agentProfile.reorder',
      <String, Object?>{
        'ids': profileIds,
        'expectedRevisions': expectedRevisions,
      },
      const <String, String>{
        aleraRuntimeHostAgentProfileOrderingCapability:
            'Reordering agent profiles requires a newer runtime host. Restart '
            'Alera to replace the running host.',
        aleraRuntimeHostAgentProfileRevisionsCapability:
            'Safe agent profile editing requires a newer runtime host. Restart '
            'Alera to replace the running host.',
      },
    );
    return _profileListFromPayload(payload);
  }

  Future<Object?> _mutationRequest(
    String type,
    Map<String, Object?> payload,
    Map<String, String> requiredCapabilities,
  ) {
    if (requiredCapabilities.isEmpty) {
      return _client.runtimeRequest(type, payload);
    }
    final client = _client;
    if (client is! GuardedRuntimeHostClient) {
      throw StateError(
        'The runtime client cannot safely validate host capabilities for this '
        'agent profile mutation.',
      );
    }
    final guardedClient = client as GuardedRuntimeHostClient;
    return guardedClient.guardedRuntimeRequest(
      type,
      payload,
      validateStatus: (status) {
        final capabilities = status['runtimeCapabilities'];
        for (final requirement in requiredCapabilities.entries) {
          if (capabilities is! List ||
              !capabilities.contains(requirement.key)) {
            throw StateError(requirement.value);
          }
        }
      },
    );
  }

  Future<AgentProfileRemovalImpact> removalImpact(
    String profileId, {
    required int expectedRevision,
  }) async {
    await beforeAccess?.call();
    final payload = await _mutationRequest(
      'agentProfile.removalImpact',
      <String, Object?>{'id': profileId, 'expectedRevision': expectedRevision},
      const <String, String>{
        aleraRuntimeHostAgentProfileRevisionsCapability:
            'Safe agent profile editing requires a newer runtime host. Restart '
            'Alera to replace the running host.',
        aleraRuntimeHostAgentProfileRemovalCapability:
            'Deleting agent profiles requires a newer runtime host. Restart '
            'Alera to replace the running host.',
      },
    );
    return AgentProfileRemovalImpact.fromJson(_mapFromPayload(payload));
  }

  Future<void> remove(
    String profileId, {
    required int expectedRevision,
    required bool confirmed,
  }) async {
    await beforeAccess?.call();
    await _mutationRequest(
      'agentProfile.remove',
      <String, Object?>{
        'id': profileId,
        'expectedRevision': expectedRevision,
        'confirmed': confirmed,
      },
      const <String, String>{
        aleraRuntimeHostAgentProfileRevisionsCapability:
            'Safe agent profile editing requires a newer runtime host. Restart '
            'Alera to replace the running host.',
        aleraRuntimeHostAgentProfileRemovalCapability:
            'Deleting agent profiles requires a newer runtime host. Restart '
            'Alera to replace the running host.',
      },
    );
  }
}

List<AgentProfile> _profileListFromPayload(Object? payload) {
  final items = payload is Map ? payload['items'] : payload;
  if (items is List) {
    return <AgentProfile>[
      for (final item in items)
        if (item is Map) AgentProfile.fromJson(Map<String, Object?>.from(item)),
    ];
  }
  throw const FormatException(
    'Runtime agent profile payload must carry a JSON list of items.',
  );
}

Map<String, Object?> _mapFromPayload(Object? payload) {
  if (payload is Map) {
    return Map<String, Object?>.from(payload);
  }
  throw const FormatException(
    'Runtime agent profile payload must be a JSON object.',
  );
}

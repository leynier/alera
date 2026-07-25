import 'dart:async';

import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
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
    required String name,
    required String agentType,
    required String command,
    String description = '',
    String? quotaGroup,
  }) async {
    await beforeAccess?.call();
    final payload = await _client
        .runtimeRequest('agentProfile.upsert', <String, Object?>{
          'id': ?id,
          'name': name,
          'agentType': agentType,
          'command': command,
          'description': description,
          'quotaGroup': quotaGroup,
        });
    return AgentProfile.fromJson(_mapFromPayload(payload));
  }

  Future<void> remove(String profileId) async {
    await beforeAccess?.call();
    await _client.runtimeRequest('agentProfile.remove', <String, Object?>{
      'id': profileId,
    });
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

import 'dart:async';

import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/infra/runtime_agent_profile_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves the order received from the runtime host', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['agentProfile.list'] = <String, Object?>{
      'items': <Object?>[
        _profilePayload('prof_2', 'Beta'),
        _profilePayload('prof_1', 'Alpha'),
      ],
    };
    final repository = RuntimeAgentProfileRepository(client);
    final container = ProviderContainer(
      overrides: [agentProfileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(() {
      container.dispose();
      client.close();
    });

    final profiles = await container.read(agentProfilesProvider.future);

    expect(profiles.map((profile) => profile.id), <String>['prof_2', 'prof_1']);
  });
}

Map<String, Object?> _profilePayload(String id, String name) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'agentType': 'codex',
    'command': 'codex',
    'customPrompt': '',
    'description': '',
    'quotaGroup': null,
    'createdAt': '2026-07-01T00:00:00.000Z',
    'updatedAt': '2026-07-01T00:00:00.000Z',
  };
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    return responses[type];
  }

  void close() {
    _events.close();
  }
}

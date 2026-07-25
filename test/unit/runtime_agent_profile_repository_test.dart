import 'dart:async';

import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_profiles/infra/runtime_agent_profile_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentProfile', () {
    test('parses a host payload and round-trips it', () {
      final profile = AgentProfile.fromJson(<String, Object?>{
        'id': 'prof_1',
        'name': 'Codex Sol',
        'agentType': 'codex',
        'command': 'codex --model gpt-5.6-sol',
        'description': 'Backend implementation',
        'quotaGroup': 'codex-personal',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'updatedAt': '2026-07-02T00:00:00.000Z',
      });

      expect(profile.name, 'Codex Sol');
      expect(profile.agentType, 'codex');
      expect(profile.command, 'codex --model gpt-5.6-sol');
      expect(profile.quotaGroup, 'codex-personal');
      expect(profile.createdAt, DateTime.utc(2026, 7));
      expect(profile.toJson()['quotaGroup'], 'codex-personal');
    });

    test('treats a blank quota group and description as absent', () {
      final profile = AgentProfile.fromJson(<String, Object?>{
        'id': 'prof_1',
        'name': 'Codex Sol',
        'agentType': 'codex',
        'command': 'codex',
        'description': '   ',
        'quotaGroup': '   ',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'updatedAt': '2026-07-01T00:00:00.000Z',
      });

      expect(profile.description, isEmpty);
      expect(profile.quotaGroup, isNull);
    });

    test('rejects a payload missing a required field', () {
      expect(
        () => AgentProfile.fromJson(<String, Object?>{
          'id': 'prof_1',
          'name': 'Codex Sol',
          'agentType': 'codex',
          'createdAt': '2026-07-01T00:00:00.000Z',
          'updatedAt': '2026-07-01T00:00:00.000Z',
        }),
        throwsFormatException,
      );
    });

    test('clearing the quota group survives copyWith', () {
      final profile = AgentProfile.fromJson(<String, Object?>{
        'id': 'prof_1',
        'name': 'Codex Sol',
        'agentType': 'codex',
        'command': 'codex',
        'quotaGroup': 'codex-personal',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'updatedAt': '2026-07-01T00:00:00.000Z',
      });

      expect(profile.copyWith(clearQuotaGroup: true).quotaGroup, isNull);
      expect(profile.copyWith(name: 'Renamed').quotaGroup, 'codex-personal');
    });
  });

  group('spawnableAgentProfileAdapters', () {
    test('matches the eight adapters the host registry supports', () {
      expect(
        spawnableAgentProfileAdapters.map((adapter) => adapter.key).toList(),
        <String>[
          'codex',
          'claude',
          'copilot',
          'cursor',
          'agy',
          'opencode',
          'pi',
          'amp',
        ],
      );
      // grok is a hook agent with no spawn adapter, so no profile may target it.
      expect(agentProfileAdapterFromKey('grok'), isNull);
      expect(agentProfileAdapterFromKey('codex'), isNotNull);
    });

    test('every adapter declares a default command', () {
      for (final adapter in spawnableAgentProfileAdapters) {
        expect(
          agentProfileDefaultCommands[adapter],
          isNotNull,
          reason: 'missing default command for ${adapter.key}',
        );
      }
    });
  });

  group('RuntimeAgentProfileRepository', () {
    test('list unwraps the collection envelope', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['agentProfile.list'] = <String, Object?>{
        'kind': 'agentProfiles',
        'items': <Object?>[_profilePayload('prof_1', 'Codex Sol')],
        'filters': <String, Object?>{},
      };
      final repository = RuntimeAgentProfileRepository(client);

      final profiles = await repository.list();

      expect(profiles, hasLength(1));
      expect(profiles.single.name, 'Codex Sol');
    });

    test('upsert omits the id when creating a profile', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['agentProfile.upsert'] = _profilePayload(
        'prof_1',
        'Codex Sol',
      );
      final repository = RuntimeAgentProfileRepository(client);

      await repository.upsert(
        name: 'Codex Sol',
        agentType: 'codex',
        command: 'codex',
      );

      final payload = client.payloads['agentProfile.upsert']!.single;
      expect(payload.containsKey('id'), isFalse);
      expect(payload['name'], 'Codex Sol');
      expect(payload['quotaGroup'], isNull);
    });

    test('upsert sends the id when updating a profile', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['agentProfile.upsert'] = _profilePayload(
        'prof_1',
        'Renamed',
      );
      final repository = RuntimeAgentProfileRepository(client);

      await repository.upsert(
        id: 'prof_1',
        name: 'Renamed',
        agentType: 'codex',
        command: 'codex',
        quotaGroup: 'codex-personal',
      );

      final payload = client.payloads['agentProfile.upsert']!.single;
      expect(payload['id'], 'prof_1');
      expect(payload['quotaGroup'], 'codex-personal');
    });

    test('watchAll refreshes when the host reports a catalog change', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['agentProfile.list'] = <String, Object?>{
        'kind': 'agentProfiles',
        'items': <Object?>[_profilePayload('prof_1', 'Codex Sol')],
        'filters': <String, Object?>{},
      };
      final repository = RuntimeAgentProfileRepository(client);
      final seen = <int>[];
      final subscription = repository.watchAll().listen(
        (profiles) => seen.add(profiles.length),
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(seen, <int>[1], reason: 'initial fetch');
      client.responses['agentProfile.list'] = <String, Object?>{
        'kind': 'agentProfiles',
        'items': <Object?>[
          _profilePayload('prof_1', 'Codex Sol'),
          _profilePayload('prof_2', 'Claude Sonnet'),
        ],
        'filters': <String, Object?>{},
      };
      client.emit(
        const RuntimeHostEvent('agentProfilesChanged', <String, Object?>{}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(seen, containsAllInOrder(<int>[1, 2]));
      await subscription.cancel();
      client.close();
    });
  });
}

Map<String, Object?> _profilePayload(String id, String name) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'agentType': 'codex',
    'command': 'codex',
    'description': '',
    'quotaGroup': null,
    'createdAt': '2026-07-01T00:00:00.000Z',
    'updatedAt': '2026-07-01T00:00:00.000Z',
  };
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final payloads = <String, List<Map<String, Object?>>>{};
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    return responses[type];
  }

  void emit(RuntimeHostEvent event) {
    _events.add(event);
  }

  void close() {
    _events.close();
  }
}

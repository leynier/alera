import 'dart:async';

import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_removal_impact.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_profiles/infra/runtime_agent_profile_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'runtime_agent_profile_repository_revision_cases.dart';
part 'runtime_agent_profile_repository_removal_cases.dart';

void main() {
  group('AgentProfile', () {
    test('parses a host payload and round-trips it', () {
      final profile = AgentProfile.fromJson(<String, Object?>{
        'id': 'prof_1',
        'name': 'Codex Sol',
        'agentType': 'codex',
        'command': 'codex --model gpt-5.6-sol',
        'customPrompt': 'Prefer Small, Reviewable Changes',
        'description': 'Backend implementation',
        'quotaGroup': 'codex-personal',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'updatedAt': '2026-07-02T00:00:00.000Z',
        'revision': 7,
      });

      expect(profile.name, 'Codex Sol');
      expect(profile.agentType, 'codex');
      expect(profile.command, 'codex --model gpt-5.6-sol');
      expect(profile.customPrompt, 'Prefer Small, Reviewable Changes');
      expect(profile.launchMode, AgentProfileLaunchMode.command);
      expect(profile.quotaGroup, 'codex-personal');
      expect(profile.createdAt, DateTime.utc(2026, 7));
      expect(profile.revision, 7);
      expect(profile.toJson()['quotaGroup'], 'codex-personal');
      expect(
        profile.toJson()['customPrompt'],
        'Prefer Small, Reviewable Changes',
      );
      expect(profile.toJson()['revision'], 7);
    });

    test('parses managed configuration from a host payload', () {
      final profile = AgentProfile.fromJson(<String, Object?>{
        'id': 'prof_1',
        'name': 'Managed Codex',
        'agentType': 'codex',
        'command': 'codex --model gpt-5.6-sol',
        'launchMode': 'managed',
        'managedConfig': <String, Object?>{
          'model': 'gpt-5.6-sol',
          'webSearch': true,
        },
        'createdAt': '2026-07-01T00:00:00.000Z',
        'updatedAt': '2026-07-02T00:00:00.000Z',
      });

      expect(profile.launchMode, AgentProfileLaunchMode.managed);
      expect(profile.managedConfig['model'], 'gpt-5.6-sol');
      expect(profile.toJson()['managedConfig'], profile.managedConfig);
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

    test('falls back to the epoch for an unparseable timestamp', () {
      final profile = AgentProfile.fromJson(<String, Object?>{
        'id': 'prof_1',
        'name': 'Codex Sol',
        'agentType': 'codex',
        'command': 'codex',
        'createdAt': 'not-a-date',
        'updatedAt': 42,
      });

      final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      expect(profile.createdAt, epoch);
      expect(profile.updatedAt, epoch);
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
    test('matches the adapters the host registry supports', () {
      expect(
        spawnableAgentProfileAdapters.map((adapter) => adapter.key).toList(),
        <String>[
          'codex',
          'claude',
          'copilot',
          'cursor',
          'agy',
          'opencode',
          'opencode2',
          'pi',
          'amp',
          'grok',
          'fx',
        ],
      );
      expect(agentProfileAdapterFromKey('fx'), AgentType.fx);
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
        launchMode: AgentProfileLaunchMode.command,
        command: 'codex',
        customPrompt: 'Prefer Small, Reviewable Changes',
      );

      final payload = client.payloads['agentProfile.upsert']!.single;
      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('expectedRevision'), isFalse);
      expect(payload['name'], 'Codex Sol');
      expect(payload['launchMode'], 'command');
      expect(payload['quotaGroup'], isNull);
      expect(payload['customPrompt'], 'Prefer Small, Reviewable Changes');
    });

    _registerAgentProfileRevisionRepositoryTests();
    _registerAgentProfileRemovalRepositoryTests();

    test('controller clone reuses all profile fields without its id', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['agentProfile.upsert'] = <String, Object?>{
        ..._profilePayload('prof_2', 'Codex Sol Copy'),
        'description': 'Backend implementation',
        'quotaGroup': 'codex-personal',
      };
      final repository = RuntimeAgentProfileRepository(client);
      final container = ProviderContainer(
        overrides: [
          agentProfileRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() {
        container.dispose();
        client.close();
      });
      client.responses['agentProfile.list'] = <String, Object?>{
        'items': <Object?>[],
      };
      await container.read(agentProfilesProvider.future);

      final source = AgentProfile(
        id: 'prof_1',
        name: 'Codex Sol',
        agentType: 'codex',
        command: 'codex --model sol',
        description: 'Backend implementation',
        customPrompt: 'Prefer Small, Reviewable Changes',
        quotaGroup: 'codex-personal',
        createdAt: DateTime.utc(2026, 7),
        updatedAt: DateTime.utc(2026, 7),
      );
      await container
          .read(agentProfilesProvider.notifier)
          .clone(source, name: 'Codex Sol Copy');

      final payload = client.payloads['agentProfile.upsert']!.single;
      expect(payload.containsKey('id'), isFalse);
      expect(payload['name'], 'Codex Sol Copy');
      expect(payload['command'], 'codex --model sol');
      expect(payload['description'], 'Backend implementation');
      expect(payload['quotaGroup'], 'codex-personal');
      expect(payload['customPrompt'], 'Prefer Small, Reviewable Changes');
    });

    test('managed upsert sends structured config and no raw command', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['status.get'] = <String, Object?>{
        'runtimeCapabilities': <String>[
          aleraRuntimeHostManagedAgentProfilesCapability,
        ],
      };
      client.responses['agentProfile.upsert'] = <String, Object?>{
        ..._profilePayload('prof_1', 'Managed Codex'),
        'launchMode': 'managed',
        'managedConfig': <String, Object?>{
          'model': 'gpt-5.6-sol',
          'webSearch': true,
        },
      };
      final repository = RuntimeAgentProfileRepository(client);

      await repository.upsert(
        name: 'Managed Codex',
        agentType: 'codex',
        launchMode: AgentProfileLaunchMode.managed,
        command: 'this must not be trusted',
        managedConfig: const <String, Object?>{
          'model': 'gpt-5.6-sol',
          'webSearch': true,
        },
      );

      final payload = client.payloads['agentProfile.upsert']!.single;
      expect(payload['launchMode'], 'managed');
      expect(payload['command'], isEmpty);
      expect(payload['managedConfig'], <String, Object?>{
        'model': 'gpt-5.6-sol',
        'webSearch': true,
      });
    });

    test('managed upsert refuses an older live host', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['status.get'] = <String, Object?>{
        'runtimeCapabilities': <String>[
          aleraRuntimeHostOrchestrationCapability,
        ],
      };
      final repository = RuntimeAgentProfileRepository(client);

      await expectLater(
        repository.upsert(
          name: 'Managed Codex',
          agentType: 'codex',
          launchMode: AgentProfileLaunchMode.managed,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Restart Alera'),
          ),
        ),
      );
      expect(client.payloads['agentProfile.upsert'], isNull);
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

  group('AgentProfiles controller', () {
    test('keeps a saved mutation over a delayed stale snapshot', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['agentProfile.list'] = <String, Object?>{
        'items': <Object?>[_profilePayload('prof_1', 'Old Name')],
      };
      client.responses['agentProfile.upsert'] = <String, Object?>{
        ..._profilePayload('prof_1', 'New Name'),
        'revision': 1,
      };
      client.responses['status.get'] = <String, Object?>{
        'runtimeCapabilities': <String>[
          aleraRuntimeHostAgentProfileRevisionsCapability,
        ],
      };
      final repository = RuntimeAgentProfileRepository(client);
      final container = ProviderContainer(
        overrides: [
          agentProfileRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() {
        container.dispose();
        client.close();
      });
      await container.read(agentProfilesProvider.future);

      await container
          .read(agentProfilesProvider.notifier)
          .upsert(
            id: 'prof_1',
            expectedRevision: 0,
            name: 'New Name',
            agentType: 'codex',
            launchMode: AgentProfileLaunchMode.command,
            command: 'codex',
          );

      expect(
        container.read(agentProfilesProvider).requireValue.single.name,
        'New Name',
      );

      client.emit(
        const RuntimeHostEvent('agentProfilesChanged', <String, Object?>{}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        container.read(agentProfilesProvider).requireValue.single.name,
        'New Name',
      );
    });
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
    'revision': 0,
    'createdAt': '2026-07-01T00:00:00.000Z',
    'updatedAt': '2026-07-01T00:00:00.000Z',
  };
}

final class _FakeRuntimeHostClient
    implements RuntimeHostClient, GuardedRuntimeHostClient {
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

  @override
  Future<Object?> guardedRuntimeRequest(
    String type,
    Map<String, Object?> payload, {
    required void Function(Map<String, Object?> status) validateStatus,
    Duration? timeout,
  }) async {
    final status = await runtimeRequest('status.get');
    validateStatus(Map<String, Object?>.from(status! as Map));
    return runtimeRequest(type, payload, timeout);
  }

  void emit(RuntimeHostEvent event) {
    _events.add(event);
  }

  void close() {
    _events.close();
  }
}

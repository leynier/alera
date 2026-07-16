import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_quota_providers.g.dart';

const agentQuotaRefreshInterval = Duration(minutes: 5);

@Riverpod(keepAlive: true)
RuntimeProxyClient runtimeProxyClient(Ref ref) {
  return RuntimeProxyClient(processRunner: ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
AgentQuotaService agentQuotaService(Ref ref) {
  return AgentQuotaService(ref.watch(runtimeProxyClientProvider));
}

@Riverpod(keepAlive: true)
Future<AgentQuotaState> agentQuotaState(Ref ref) async {
  final hostId = ref.watch(
    workbenchControllerProvider.select(
      (state) => state.activeWorkspace?.hostId ?? 'local',
    ),
  );
  ref.watch(
    settingsControllerProvider.select(
      (settings) =>
          agentQuotaRequestKey(settings.agents.quotas.forHost(hostId)),
    ),
  );
  final settings = ref
      .read(settingsControllerProvider)
      .agents
      .quotas
      .forHost(hostId);
  final targets = ref.watch(sshTargetsProvider).value ?? const <SshTarget>[];
  final target = hostId == 'local'
      ? null
      : targets.where((candidate) => candidate.id == hostId).firstOrNull;
  final timer = Timer(agentQuotaRefreshInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref
      .watch(agentQuotaServiceProvider)
      .fetch(hostId: hostId, target: target, settings: settings);
}

String agentQuotaRequestKey(AgentQuotaHostSettings settings) {
  final providers =
      settings.enabledProviders.map((provider) => provider.name).toList()
        ..sort();
  final profiles =
      settings.claudeProfiles
          .map(
            (profile) => <String, String>{
              'alias': profile.alias,
              'profile': profile.profile,
            },
          )
          .toList()
        ..sort((left, right) {
          final byProfile = left['profile']!.compareTo(right['profile']!);
          return byProfile != 0
              ? byProfile
              : left['alias']!.compareTo(right['alias']!);
        });
  return jsonEncode(<String, Object?>{
    'providers': providers,
    'claudeDefaultEnabled': settings.claudeDefaultEnabled,
    'claudeProfiles': profiles,
    'environment': settings.environment.toJson(),
  });
}

class AgentQuotaService {
  AgentQuotaService(this._client);

  final RuntimeProxyClient _client;
  final Map<String, AgentQuotaState> _cache = <String, AgentQuotaState>{};

  Future<AgentQuotaState> fetch({
    required String hostId,
    required SshTarget? target,
    required AgentQuotaHostSettings settings,
  }) async {
    try {
      final payload = await _client.request(
        hostId: hostId,
        target: target,
        type: 'agentQuota.fetch',
        payload: <String, Object?>{
          'providers': <String>[
            for (final provider in settings.enabledProviders) provider.name,
          ],
          'claudeDefaultEnabled': settings.claudeDefaultEnabled,
          'claudeProfiles': <Map<String, String>>[
            for (final profile in settings.claudeProfiles)
              <String, String>{
                'alias': profile.alias,
                'profile': profile.profile,
              },
          ],
          'environmentNames': <String, String>{
            'kimiApiKey': settings.environment.kimiApiKey,
            'zaiApiKey': settings.environment.zaiApiKey,
            'zaiBaseUrl': settings.environment.zaiBaseUrl,
            'minimaxApiKey': settings.environment.minimaxApiKey,
            'minimaxApiHost': settings.environment.minimaxApiHost,
          },
        },
      );
      final fresh = <AgentQuotaSnapshot>[
        for (final item in (payload['snapshots'] as List? ?? const <Object?>[]))
          if (item is Map)
            AgentQuotaSnapshot.fromJson(Map<String, Object?>.from(item)),
      ];
      final previous = <String, AgentQuotaSnapshot>{
        for (final snapshot
            in _cache[hostId]?.snapshots ?? const <AgentQuotaSnapshot>[])
          snapshot.key: snapshot,
      };
      final merged = <AgentQuotaSnapshot>[
        for (final snapshot in fresh)
          if (snapshot.status == AgentQuotaStatus.ok ||
              !previous.containsKey(snapshot.key))
            _markOldSnapshotStale(snapshot)
          else
            previous[snapshot.key]!.asStale(snapshot.error),
      ];
      final state = AgentQuotaState(
        hostId: hostId,
        snapshots: merged,
        environment: _boolMap(payload['environment']),
        fetchedAt: DateTime.now().toUtc(),
      );
      _cache[hostId] = state;
      return state;
    } catch (error) {
      final previous = _cache[hostId];
      if (previous != null) {
        return AgentQuotaState(
          hostId: hostId,
          snapshots: <AgentQuotaSnapshot>[
            for (final snapshot in previous.snapshots)
              snapshot.asStale(error.toString()),
          ],
          environment: previous.environment,
          fetchedAt: previous.fetchedAt,
          error: error.toString(),
        );
      }
      return AgentQuotaState(
        hostId: hostId,
        snapshots: const <AgentQuotaSnapshot>[],
        environment: const <String, bool>{},
        fetchedAt: DateTime.now().toUtc(),
        error: error.toString(),
      );
    }
  }
}

AgentQuotaSnapshot _markOldSnapshotStale(AgentQuotaSnapshot snapshot) {
  if (DateTime.now().toUtc().difference(snapshot.updatedAt) >
      const Duration(minutes: 30)) {
    return snapshot.asStale(snapshot.error);
  }
  return snapshot;
}

Map<String, bool> _boolMap(Object? value) {
  if (value is! Map) {
    return const <String, bool>{};
  }
  return <String, bool>{
    for (final entry in value.entries)
      if (entry.key is String && entry.value is bool)
        entry.key as String: entry.value as bool,
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

import 'dart:async';

import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_loader.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_profile_selection.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_snapshot_cache.dart';
import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:alera/src/features/agent_usage/infra/file_agent_usage_snapshot_cache.dart';
import 'package:alera/src/features/agent_usage/infra/runtime_agent_usage_loader.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_usage_providers.g.dart';

class AgentUsageState {
  const AgentUsageState({
    required this.snapshot,
    this.refreshing = false,
    this.error,
  });

  final AgentUsageSnapshot snapshot;
  final bool refreshing;
  final String? error;
}

@Riverpod(keepAlive: true)
AgentUsageSnapshotCache agentUsageSnapshotCache(Ref ref) {
  return FileAgentUsageSnapshotCache();
}

@Riverpod(keepAlive: true)
AgentUsageLoader agentUsageLoader(Ref ref) {
  return RuntimeAgentUsageLoader(
    ref.watch(runtimeHostClientProvider),
    ref.watch(runtimeProxyClientProvider),
  );
}

@riverpod
class AgentUsage extends _$AgentUsage {
  AgentUsageRequest? _request;
  Object? _generation;
  Future<void>? _refreshInFlight;
  bool _disposed = false;

  @override
  FutureOr<AgentUsageState> build(int days) {
    _disposed = false;
    final hostId = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.activeWorkspace?.hostId ?? 'local',
      ),
    );
    final settings = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.agents.quotas.forHost(hostId),
      ),
    );
    final targets = ref.watch(sshTargetsProvider).value ?? const <SshTarget>[];
    final target = hostId == 'local'
        ? null
        : targets.where((candidate) => candidate.id == hostId).firstOrNull;
    final now = DateTime.now();
    final until = DateTime(now.year, now.month, now.day);
    final request = AgentUsageRequest(
      hostId: hostId,
      target: target,
      settings: settings,
      sinceDay: _usageDay(until.subtract(Duration(days: days - 1))),
      untilDay: _usageDay(until),
    );
    final generation = Object();
    _request = request;
    _generation = generation;
    _refreshInFlight = null;
    ref.onDispose(() => _disposed = true);

    final cache = ref.watch(agentUsageSnapshotCacheProvider);
    final memory = cache.peek(hostId: hostId, days: days);
    if (memory != null) {
      final snapshot = _snapshotFor(request, memory);
      _scheduleRefresh(request, snapshot, generation);
      return AgentUsageState(snapshot: snapshot, refreshing: true);
    }
    return _loadCachedOrFresh(request, days, generation);
  }

  Future<void> refresh() {
    final request = _request;
    final generation = _generation;
    if (request == null || generation == null) return Future<void>.value();
    return _startRefresh(request, state.value?.snapshot, generation, days);
  }

  Future<AgentUsageState> _loadCachedOrFresh(
    AgentUsageRequest request,
    int days,
    Object generation,
  ) async {
    final cache = ref.read(agentUsageSnapshotCacheProvider);
    final cached = await cache.read(hostId: request.hostId, days: days);
    if (cached != null) {
      final snapshot = _snapshotFor(request, cached);
      _scheduleRefresh(request, snapshot, generation);
      return AgentUsageState(snapshot: snapshot, refreshing: true);
    }
    final response = await ref.read(agentUsageLoaderProvider).fetch(request);
    final snapshot = _snapshotFor(request, response);
    await _writeCacheBestEffort(request.hostId, days, response);
    return AgentUsageState(snapshot: snapshot);
  }

  void _scheduleRefresh(
    AgentUsageRequest request,
    AgentUsageSnapshot snapshot,
    Object generation,
  ) {
    Timer.run(() {
      if (!_isCurrent(generation)) return;
      unawaited(_startRefresh(request, snapshot, generation, days));
    });
  }

  Future<void> _startRefresh(
    AgentUsageRequest request,
    AgentUsageSnapshot? previous,
    Object generation,
    int days,
  ) {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final operation = _performRefresh(request, previous, generation, days);
    _refreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    });
  }

  Future<void> _performRefresh(
    AgentUsageRequest request,
    AgentUsageSnapshot? previous,
    Object generation,
    int days,
  ) async {
    if (previous != null && _isCurrent(generation)) {
      state = AsyncData(AgentUsageState(snapshot: previous, refreshing: true));
    } else if (_isCurrent(generation)) {
      state = const AsyncLoading<AgentUsageState>();
    }
    try {
      final response = await ref.read(agentUsageLoaderProvider).fetch(request);
      final snapshot = _snapshotFor(request, response);
      await _writeCacheBestEffort(request.hostId, days, response);
      if (_isCurrent(generation)) {
        state = AsyncData(AgentUsageState(snapshot: snapshot));
      }
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;
      if (previous != null) {
        state = AsyncData(
          AgentUsageState(snapshot: previous, error: error.toString()),
        );
      } else {
        state = AsyncError<AgentUsageState>(error, stackTrace);
      }
    }
  }

  Future<void> _writeCacheBestEffort(
    String hostId,
    int days,
    Map<String, Object?> response,
  ) async {
    try {
      await ref
          .read(agentUsageSnapshotCacheProvider)
          .write(hostId: hostId, days: days, snapshot: response);
    } on Object {
      // Fresh usage remains usable when the local cache is unavailable.
    }
  }

  bool _isCurrent(Object generation) {
    return !_disposed && identical(_generation, generation);
  }

  AgentUsageSnapshot _snapshotFor(
    AgentUsageRequest request,
    Map<String, Object?> response,
  ) {
    return AgentUsageSnapshot.fromJson(response).withClaudeProfileSelection(
      defaultEnabled: request.settings.claudeDefaultShowInUsage,
      profileLabels: <String, String>{
        for (final profile in request.settings.claudeProfiles)
          if (profile.showInUsage) profile.profile: profile.usageLabel,
      },
    );
  }
}

String _usageDay(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

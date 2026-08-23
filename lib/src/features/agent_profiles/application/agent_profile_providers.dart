import 'dart:async';

import 'package:alera/src/features/agent_profiles/application/agent_profile_persona_discovery.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/infra/runtime_agent_profile_repository.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_profile_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeAgentProfileRepository agentProfileRepository(Ref ref) {
  return RuntimeAgentProfileRepository(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
AgentProfilePersonaDiscovery agentProfilePersonaDiscovery(Ref ref) {
  return AgentProfilePersonaDiscovery(
    processRunner: ref.read(processRunnerProvider),
    commandEnvironmentResolver: ref.read(commandEnvironmentResolverProvider),
  );
}

@Riverpod(keepAlive: true)
class AgentProfiles extends _$AgentProfiles {
  final Map<String, AgentProfile> _pendingUpserts = <String, AgentProfile>{};
  final Set<String> _pendingRemovals = <String>{};
  List<AgentProfile> _latestSnapshot = const <AgentProfile>[];
  StreamSubscription<List<AgentProfile>>? _subscription;

  RuntimeAgentProfileRepository get _repository =>
      ref.read(agentProfileRepositoryProvider);

  @override
  Future<List<AgentProfile>> build() {
    _pendingUpserts.clear();
    _pendingRemovals.clear();
    _latestSnapshot = const <AgentProfile>[];
    final firstSnapshot = Completer<List<AgentProfile>>();
    _subscription = ref
        .watch(agentProfileRepositoryProvider)
        .watchAll()
        .listen(
          (profiles) {
            _latestSnapshot = profiles;
            final merged = _mergeSnapshot(profiles);
            if (!firstSnapshot.isCompleted) {
              firstSnapshot.complete(merged);
            } else {
              state = AsyncData<List<AgentProfile>>(merged);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!firstSnapshot.isCompleted) {
              firstSnapshot.completeError(error, stackTrace);
            } else {
              state = AsyncError<List<AgentProfile>>(error, stackTrace);
            }
          },
        );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return firstSnapshot.future;
  }

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
    final saved = await _repository.upsert(
      id: id,
      expectedRevision: expectedRevision,
      name: name,
      agentType: agentType,
      launchMode: launchMode,
      command: command,
      managedConfig: managedConfig,
      customPrompt: customPrompt,
      description: description,
      quotaGroup: quotaGroup,
    );
    _pendingRemovals.remove(saved.id);
    _pendingUpserts[saved.id] = saved;
    state = AsyncData<List<AgentProfile>>(_mergeSnapshot(_latestSnapshot));
    return saved;
  }

  Future<List<AgentProfile>> reorder(List<String> profileIds) async {
    final current = state.asData?.value ?? _mergeSnapshot(_latestSnapshot);
    final byId = <String, AgentProfile>{
      for (final profile in current) profile.id: profile,
    };
    final optimistic = <AgentProfile>[];
    for (final profileId in profileIds) {
      final profile = byId[profileId];
      if (profile == null) {
        return current;
      }
      optimistic.add(profile);
    }
    if (optimistic.length != current.length) {
      return current;
    }
    state = AsyncData<List<AgentProfile>>(optimistic);
    try {
      final reordered = await _repository.reorder(
        profileIds,
        expectedRevisions: <String, int>{
          for (final profile in current) profile.id: profile.revision,
        },
      );
      _latestSnapshot = reordered;
      _pendingUpserts.clear();
      _pendingRemovals.clear();
      state = AsyncData<List<AgentProfile>>(reordered);
      return reordered;
    } catch (_) {
      state = AsyncData<List<AgentProfile>>(_mergeSnapshot(_latestSnapshot));
      rethrow;
    }
  }

  Future<AgentProfile> clone(AgentProfile source, {required String name}) {
    return upsert(
      name: name,
      agentType: source.agentType,
      launchMode: source.launchMode,
      command: source.command,
      managedConfig: <String, Object?>{...source.managedConfig},
      customPrompt: source.customPrompt,
      description: source.description,
      quotaGroup: source.quotaGroup,
    );
  }

  Future<void> remove(String profileId, {required int expectedRevision}) async {
    await _repository.remove(profileId, expectedRevision: expectedRevision);
    _pendingUpserts.remove(profileId);
    _pendingRemovals.add(profileId);
    state = AsyncData<List<AgentProfile>>(_mergeSnapshot(_latestSnapshot));
  }

  List<AgentProfile> _mergeSnapshot(List<AgentProfile> profiles) {
    final authoritativeById = <String, AgentProfile>{
      for (final profile in profiles) profile.id: profile,
    };
    for (final pending in _pendingUpserts.values.toList(growable: false)) {
      final authoritative = authoritativeById[pending.id];
      if (authoritative != null &&
          (authoritative.updatedAt.isAfter(pending.updatedAt) ||
              (authoritative.updatedAt == pending.updatedAt &&
                  _sameProfile(authoritative, pending)))) {
        _pendingUpserts.remove(pending.id);
      }
    }
    for (final profileId in _pendingRemovals.toList(growable: false)) {
      if (!authoritativeById.containsKey(profileId)) {
        _pendingRemovals.remove(profileId);
      }
    }
    final mergedById = <String, AgentProfile>{
      for (final profile in profiles)
        if (!_pendingRemovals.contains(profile.id)) profile.id: profile,
      ..._pendingUpserts,
    };
    return mergedById.values.toList(growable: false);
  }

  bool _sameProfile(AgentProfile left, AgentProfile right) {
    return left.id == right.id &&
        left.revision == right.revision &&
        left.name == right.name &&
        left.agentType == right.agentType &&
        left.command == right.command &&
        left.launchMode == right.launchMode &&
        _sameConfig(left.managedConfig, right.managedConfig) &&
        left.customPrompt == right.customPrompt &&
        left.description == right.description &&
        left.quotaGroup == right.quotaGroup;
  }

  bool _sameConfig(Map<String, Object?> left, Map<String, Object?> right) {
    return left.length == right.length &&
        left.entries.every((entry) => right[entry.key] == entry.value);
  }
}

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
    required String name,
    required String agentType,
    required AgentProfileLaunchMode launchMode,
    String command = '',
    Map<String, Object?> managedConfig = const <String, Object?>{},
    String description = '',
    String? quotaGroup,
  }) async {
    final saved = await _repository.upsert(
      id: id,
      name: name,
      agentType: agentType,
      launchMode: launchMode,
      command: command,
      managedConfig: managedConfig,
      description: description,
      quotaGroup: quotaGroup,
    );
    _pendingRemovals.remove(saved.id);
    _pendingUpserts[saved.id] = saved;
    state = AsyncData<List<AgentProfile>>(_mergeSnapshot(_latestSnapshot));
    return saved;
  }

  Future<void> remove(String profileId) async {
    await _repository.remove(profileId);
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
    final merged = mergedById.values.toList(growable: false)
      ..sort((left, right) {
        final byName = left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        );
        return byName != 0 ? byName : left.id.compareTo(right.id);
      });
    return merged;
  }

  bool _sameProfile(AgentProfile left, AgentProfile right) {
    return left.id == right.id &&
        left.name == right.name &&
        left.agentType == right.agentType &&
        left.command == right.command &&
        left.launchMode == right.launchMode &&
        _sameConfig(left.managedConfig, right.managedConfig) &&
        left.description == right.description &&
        left.quotaGroup == right.quotaGroup;
  }

  bool _sameConfig(Map<String, Object?> left, Map<String, Object?> right) {
    return left.length == right.length &&
        left.entries.every((entry) => right[entry.key] == entry.value);
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_profile_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentProfileRepository)
final agentProfileRepositoryProvider = AgentProfileRepositoryProvider._();

final class AgentProfileRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeAgentProfileRepository,
          RuntimeAgentProfileRepository,
          RuntimeAgentProfileRepository
        >
    with $Provider<RuntimeAgentProfileRepository> {
  AgentProfileRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProfileRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProfileRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeAgentProfileRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeAgentProfileRepository create(Ref ref) {
    return agentProfileRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeAgentProfileRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeAgentProfileRepository>(
        value,
      ),
    );
  }
}

String _$agentProfileRepositoryHash() =>
    r'b8d54c2d655f560e823b5be92c3e7f3888abb6ba';

@ProviderFor(agentProfilePersonaDiscovery)
final agentProfilePersonaDiscoveryProvider =
    AgentProfilePersonaDiscoveryProvider._();

final class AgentProfilePersonaDiscoveryProvider
    extends
        $FunctionalProvider<
          AgentProfilePersonaDiscovery,
          AgentProfilePersonaDiscovery,
          AgentProfilePersonaDiscovery
        >
    with $Provider<AgentProfilePersonaDiscovery> {
  AgentProfilePersonaDiscoveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProfilePersonaDiscoveryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProfilePersonaDiscoveryHash();

  @$internal
  @override
  $ProviderElement<AgentProfilePersonaDiscovery> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentProfilePersonaDiscovery create(Ref ref) {
    return agentProfilePersonaDiscovery(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentProfilePersonaDiscovery value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentProfilePersonaDiscovery>(value),
    );
  }
}

String _$agentProfilePersonaDiscoveryHash() =>
    r'df214d78c797c469176201da1dbb2dee4de4297b';

@ProviderFor(AgentProfiles)
final agentProfilesProvider = AgentProfilesProvider._();

final class AgentProfilesProvider
    extends $AsyncNotifierProvider<AgentProfiles, List<AgentProfile>> {
  AgentProfilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProfilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProfilesHash();

  @$internal
  @override
  AgentProfiles create() => AgentProfiles();
}

String _$agentProfilesHash() => r'20b0ebcacb8a2ca4c9e20bafb46f25115a3d4240';

abstract class _$AgentProfiles extends $AsyncNotifier<List<AgentProfile>> {
  FutureOr<List<AgentProfile>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<AgentProfile>>, List<AgentProfile>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<AgentProfile>>, List<AgentProfile>>,
              AsyncValue<List<AgentProfile>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

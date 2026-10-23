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

@ProviderFor(openCodeGenerationProbe)
final openCodeGenerationProbeProvider = OpenCodeGenerationProbeProvider._();

final class OpenCodeGenerationProbeProvider
    extends
        $FunctionalProvider<
          OpenCodeGenerationProbe,
          OpenCodeGenerationProbe,
          OpenCodeGenerationProbe
        >
    with $Provider<OpenCodeGenerationProbe> {
  OpenCodeGenerationProbeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'openCodeGenerationProbeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$openCodeGenerationProbeHash();

  @$internal
  @override
  $ProviderElement<OpenCodeGenerationProbe> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OpenCodeGenerationProbe create(Ref ref) {
    return openCodeGenerationProbe(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OpenCodeGenerationProbe value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OpenCodeGenerationProbe>(value),
    );
  }
}

String _$openCodeGenerationProbeHash() =>
    r'bda5a6c1988efa667a8cc70ebd46c75314fab466';

/// The installed OpenCode generation, for previews that must show the
/// command line the runtime will actually launch.

@ProviderFor(openCodeGeneration)
final openCodeGenerationProvider = OpenCodeGenerationProvider._();

/// The installed OpenCode generation, for previews that must show the
/// command line the runtime will actually launch.

final class OpenCodeGenerationProvider
    extends
        $FunctionalProvider<
          AsyncValue<OpenCodeGeneration>,
          OpenCodeGeneration,
          FutureOr<OpenCodeGeneration>
        >
    with
        $FutureModifier<OpenCodeGeneration>,
        $FutureProvider<OpenCodeGeneration> {
  /// The installed OpenCode generation, for previews that must show the
  /// command line the runtime will actually launch.
  OpenCodeGenerationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'openCodeGenerationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$openCodeGenerationHash();

  @$internal
  @override
  $FutureProviderElement<OpenCodeGeneration> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<OpenCodeGeneration> create(Ref ref) {
    return openCodeGeneration(ref);
  }
}

String _$openCodeGenerationHash() =>
    r'b9c4423583dc6b1729de4e0a6828145f09dfc5fd';

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
    r'391e39f13335a0aaedc5b8f2062ac4a07ad181b9';

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

String _$agentProfilesHash() => r'08cf89d52f8811a358872beca0374bee7e9c6572';

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

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

@ProviderFor(agentProfiles)
final agentProfilesProvider = AgentProfilesProvider._();

final class AgentProfilesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentProfile>>,
          List<AgentProfile>,
          Stream<List<AgentProfile>>
        >
    with
        $FutureModifier<List<AgentProfile>>,
        $StreamProvider<List<AgentProfile>> {
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
  $StreamProviderElement<List<AgentProfile>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AgentProfile>> create(Ref ref) {
    return agentProfiles(ref);
  }
}

String _$agentProfilesHash() => r'5c36ade6ccf07b811e3a011397428fb08919c0bc';

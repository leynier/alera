// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_title_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentTitleService)
final agentTitleServiceProvider = AgentTitleServiceProvider._();

final class AgentTitleServiceProvider
    extends
        $FunctionalProvider<
          AgentTitleService,
          AgentTitleService,
          AgentTitleService
        >
    with $Provider<AgentTitleService> {
  AgentTitleServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentTitleServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentTitleServiceHash();

  @$internal
  @override
  $ProviderElement<AgentTitleService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentTitleService create(Ref ref) {
    return agentTitleService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentTitleService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentTitleService>(value),
    );
  }
}

String _$agentTitleServiceHash() => r'8cf8cdc026f6d755534b7acff5d0abd3f07b3296';

@ProviderFor(agentTitleAvailable)
final agentTitleAvailableProvider = AgentTitleAvailableProvider._();

final class AgentTitleAvailableProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  AgentTitleAvailableProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentTitleAvailableProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentTitleAvailableHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return agentTitleAvailable(ref);
  }
}

String _$agentTitleAvailableHash() =>
    r'c9c68728de50d7b2b91ccbc5a8db83cab04dfafd';

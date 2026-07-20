// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_quota_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runtimeProxyClient)
final runtimeProxyClientProvider = RuntimeProxyClientProvider._();

final class RuntimeProxyClientProvider
    extends
        $FunctionalProvider<
          RuntimeProxyClient,
          RuntimeProxyClient,
          RuntimeProxyClient
        >
    with $Provider<RuntimeProxyClient> {
  RuntimeProxyClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeProxyClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeProxyClientHash();

  @$internal
  @override
  $ProviderElement<RuntimeProxyClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeProxyClient create(Ref ref) {
    return runtimeProxyClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeProxyClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeProxyClient>(value),
    );
  }
}

String _$runtimeProxyClientHash() =>
    r'4a49d417b1596ad9aa09937dca041bb2c2d16f17';

@ProviderFor(agentQuotaService)
final agentQuotaServiceProvider = AgentQuotaServiceProvider._();

final class AgentQuotaServiceProvider
    extends
        $FunctionalProvider<
          AgentQuotaService,
          AgentQuotaService,
          AgentQuotaService
        >
    with $Provider<AgentQuotaService> {
  AgentQuotaServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentQuotaServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentQuotaServiceHash();

  @$internal
  @override
  $ProviderElement<AgentQuotaService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentQuotaService create(Ref ref) {
    return agentQuotaService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentQuotaService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentQuotaService>(value),
    );
  }
}

String _$agentQuotaServiceHash() => r'c6aad5fd83eaa05569133c91176a90ec87215dbe';

@ProviderFor(agentQuotaState)
final agentQuotaStateProvider = AgentQuotaStateProvider._();

final class AgentQuotaStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentQuotaState>,
          AgentQuotaState,
          FutureOr<AgentQuotaState>
        >
    with $FutureModifier<AgentQuotaState>, $FutureProvider<AgentQuotaState> {
  AgentQuotaStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentQuotaStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentQuotaStateHash();

  @$internal
  @override
  $FutureProviderElement<AgentQuotaState> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentQuotaState> create(Ref ref) {
    return agentQuotaState(ref);
  }
}

String _$agentQuotaStateHash() => r'b237c82a99cea9e924f8e4c5c692a8f0a84507e1';

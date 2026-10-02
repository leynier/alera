// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_assist_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiAssistAgentRunner)
final aiAssistAgentRunnerProvider = AiAssistAgentRunnerProvider._();

final class AiAssistAgentRunnerProvider
    extends
        $FunctionalProvider<
          AiAssistAgentRunner,
          AiAssistAgentRunner,
          AiAssistAgentRunner
        >
    with $Provider<AiAssistAgentRunner> {
  AiAssistAgentRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiAssistAgentRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiAssistAgentRunnerHash();

  @$internal
  @override
  $ProviderElement<AiAssistAgentRunner> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiAssistAgentRunner create(Ref ref) {
    return aiAssistAgentRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiAssistAgentRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiAssistAgentRunner>(value),
    );
  }
}

String _$aiAssistAgentRunnerHash() =>
    r'3172b768f80dc662cfc8951f6cad4ee9e890961a';

@ProviderFor(aiAssistService)
final aiAssistServiceProvider = AiAssistServiceProvider._();

final class AiAssistServiceProvider
    extends
        $FunctionalProvider<AiAssistService, AiAssistService, AiAssistService>
    with $Provider<AiAssistService> {
  AiAssistServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiAssistServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiAssistServiceHash();

  @$internal
  @override
  $ProviderElement<AiAssistService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AiAssistService create(Ref ref) {
    return aiAssistService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiAssistService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiAssistService>(value),
    );
  }
}

String _$aiAssistServiceHash() => r'cd56a850b681aab725aabebac5e62f6077604b2f';

@ProviderFor(aiAssistModelDiscoveryService)
final aiAssistModelDiscoveryServiceProvider =
    AiAssistModelDiscoveryServiceProvider._();

final class AiAssistModelDiscoveryServiceProvider
    extends
        $FunctionalProvider<
          AiAssistModelDiscoveryService,
          AiAssistModelDiscoveryService,
          AiAssistModelDiscoveryService
        >
    with $Provider<AiAssistModelDiscoveryService> {
  AiAssistModelDiscoveryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiAssistModelDiscoveryServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiAssistModelDiscoveryServiceHash();

  @$internal
  @override
  $ProviderElement<AiAssistModelDiscoveryService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiAssistModelDiscoveryService create(Ref ref) {
    return aiAssistModelDiscoveryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiAssistModelDiscoveryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiAssistModelDiscoveryService>(
        value,
      ),
    );
  }
}

String _$aiAssistModelDiscoveryServiceHash() =>
    r'4d6f9da2d47cac48dd07e966c1245fbc76bec547';

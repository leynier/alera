// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_text_generation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiTextAgentRunner)
final aiTextAgentRunnerProvider = AiTextAgentRunnerProvider._();

final class AiTextAgentRunnerProvider
    extends
        $FunctionalProvider<
          AiTextAgentRunner,
          AiTextAgentRunner,
          AiTextAgentRunner
        >
    with $Provider<AiTextAgentRunner> {
  AiTextAgentRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiTextAgentRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiTextAgentRunnerHash();

  @$internal
  @override
  $ProviderElement<AiTextAgentRunner> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiTextAgentRunner create(Ref ref) {
    return aiTextAgentRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiTextAgentRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiTextAgentRunner>(value),
    );
  }
}

String _$aiTextAgentRunnerHash() => r'cb60dfdf9b0154ea6f9ae1e212419febc6ab82f3';

@ProviderFor(aiTextGenerationService)
final aiTextGenerationServiceProvider = AiTextGenerationServiceProvider._();

final class AiTextGenerationServiceProvider
    extends
        $FunctionalProvider<
          AiTextGenerationService,
          AiTextGenerationService,
          AiTextGenerationService
        >
    with $Provider<AiTextGenerationService> {
  AiTextGenerationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiTextGenerationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiTextGenerationServiceHash();

  @$internal
  @override
  $ProviderElement<AiTextGenerationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiTextGenerationService create(Ref ref) {
    return aiTextGenerationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiTextGenerationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiTextGenerationService>(value),
    );
  }
}

String _$aiTextGenerationServiceHash() =>
    r'36bd4cadef164d8f53bba7558462e6663d6c1d26';

@ProviderFor(aiTextModelDiscoveryService)
final aiTextModelDiscoveryServiceProvider =
    AiTextModelDiscoveryServiceProvider._();

final class AiTextModelDiscoveryServiceProvider
    extends
        $FunctionalProvider<
          AiTextModelDiscoveryService,
          AiTextModelDiscoveryService,
          AiTextModelDiscoveryService
        >
    with $Provider<AiTextModelDiscoveryService> {
  AiTextModelDiscoveryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiTextModelDiscoveryServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiTextModelDiscoveryServiceHash();

  @$internal
  @override
  $ProviderElement<AiTextModelDiscoveryService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiTextModelDiscoveryService create(Ref ref) {
    return aiTextModelDiscoveryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiTextModelDiscoveryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiTextModelDiscoveryService>(value),
    );
  }
}

String _$aiTextModelDiscoveryServiceHash() =>
    r'7c3bcd44c62867043bf9b5d188f5497492ffafd7';

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_dictation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiDictationTargetRegistry)
final aiDictationTargetRegistryProvider = AiDictationTargetRegistryProvider._();

final class AiDictationTargetRegistryProvider
    extends
        $FunctionalProvider<
          AiDictationTargetRegistry,
          AiDictationTargetRegistry,
          AiDictationTargetRegistry
        >
    with $Provider<AiDictationTargetRegistry> {
  AiDictationTargetRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiDictationTargetRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiDictationTargetRegistryHash();

  @$internal
  @override
  $ProviderElement<AiDictationTargetRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiDictationTargetRegistry create(Ref ref) {
    return aiDictationTargetRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiDictationTargetRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiDictationTargetRegistry>(value),
    );
  }
}

String _$aiDictationTargetRegistryHash() =>
    r'63cf8799f83a8f582a1bf27ac7b3f8dc4773d9cf';

@ProviderFor(aiDictationModelStore)
final aiDictationModelStoreProvider = AiDictationModelStoreProvider._();

final class AiDictationModelStoreProvider
    extends
        $FunctionalProvider<
          AiDictationModelStore,
          AiDictationModelStore,
          AiDictationModelStore
        >
    with $Provider<AiDictationModelStore> {
  AiDictationModelStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiDictationModelStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiDictationModelStoreHash();

  @$internal
  @override
  $ProviderElement<AiDictationModelStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiDictationModelStore create(Ref ref) {
    return aiDictationModelStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiDictationModelStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiDictationModelStore>(value),
    );
  }
}

String _$aiDictationModelStoreHash() =>
    r'4ab81f4f645275fda3925c5faa524c5fa68d9d3f';

@ProviderFor(aiDictationService)
final aiDictationServiceProvider = AiDictationServiceProvider._();

final class AiDictationServiceProvider
    extends
        $FunctionalProvider<
          AiDictationService,
          AiDictationService,
          AiDictationService
        >
    with $Provider<AiDictationService> {
  AiDictationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiDictationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiDictationServiceHash();

  @$internal
  @override
  $ProviderElement<AiDictationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiDictationService create(Ref ref) {
    return aiDictationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiDictationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiDictationService>(value),
    );
  }
}

String _$aiDictationServiceHash() =>
    r'ac885636e51bc9ea5b35cdbbf59718423dd023d3';

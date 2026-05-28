// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aleraUpdateHttpClient)
final aleraUpdateHttpClientProvider = AleraUpdateHttpClientProvider._();

final class AleraUpdateHttpClientProvider
    extends $FunctionalProvider<http.Client, http.Client, http.Client>
    with $Provider<http.Client> {
  AleraUpdateHttpClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraUpdateHttpClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraUpdateHttpClientHash();

  @$internal
  @override
  $ProviderElement<http.Client> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  http.Client create(Ref ref) {
    return aleraUpdateHttpClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(http.Client value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<http.Client>(value),
    );
  }
}

String _$aleraUpdateHttpClientHash() =>
    r'7e8e502af34072b3edddd69148628fbb8dcb0962';

@ProviderFor(aleraUpdateService)
final aleraUpdateServiceProvider = AleraUpdateServiceProvider._();

final class AleraUpdateServiceProvider
    extends
        $FunctionalProvider<
          AleraUpdateService,
          AleraUpdateService,
          AleraUpdateService
        >
    with $Provider<AleraUpdateService> {
  AleraUpdateServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraUpdateServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraUpdateServiceHash();

  @$internal
  @override
  $ProviderElement<AleraUpdateService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AleraUpdateService create(Ref ref) {
    return aleraUpdateService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraUpdateService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraUpdateService>(value),
    );
  }
}

String _$aleraUpdateServiceHash() =>
    r'809c06cf2512425a0479021be639090dc8f81836';

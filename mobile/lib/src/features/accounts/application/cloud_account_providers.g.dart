// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloud_account_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(cloudAccountRepository)
final cloudAccountRepositoryProvider = CloudAccountRepositoryProvider._();

final class CloudAccountRepositoryProvider
    extends
        $FunctionalProvider<
          CloudAccountRepository,
          CloudAccountRepository,
          CloudAccountRepository
        >
    with $Provider<CloudAccountRepository> {
  CloudAccountRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cloudAccountRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cloudAccountRepositoryHash();

  @$internal
  @override
  $ProviderElement<CloudAccountRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CloudAccountRepository create(Ref ref) {
    return cloudAccountRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CloudAccountRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CloudAccountRepository>(value),
    );
  }
}

String _$cloudAccountRepositoryHash() =>
    r'e60a526eb7ba4e2af8061fbea080815db35114c1';

@ProviderFor(aleraCloudConfiguration)
final aleraCloudConfigurationProvider = AleraCloudConfigurationProvider._();

final class AleraCloudConfigurationProvider
    extends
        $FunctionalProvider<
          AleraCloudConfiguration,
          AleraCloudConfiguration,
          AleraCloudConfiguration
        >
    with $Provider<AleraCloudConfiguration> {
  AleraCloudConfigurationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraCloudConfigurationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraCloudConfigurationHash();

  @$internal
  @override
  $ProviderElement<AleraCloudConfiguration> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AleraCloudConfiguration create(Ref ref) {
    return aleraCloudConfiguration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraCloudConfiguration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraCloudConfiguration>(value),
    );
  }
}

String _$aleraCloudConfigurationHash() =>
    r'6d509ec203de28fdca53ee2eff502230a8f5c147';

@ProviderFor(aleraCloudApi)
final aleraCloudApiProvider = AleraCloudApiProvider._();

final class AleraCloudApiProvider
    extends $FunctionalProvider<AleraCloudApi, AleraCloudApi, AleraCloudApi>
    with $Provider<AleraCloudApi> {
  AleraCloudApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraCloudApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraCloudApiHash();

  @$internal
  @override
  $ProviderElement<AleraCloudApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AleraCloudApi create(Ref ref) {
    return aleraCloudApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraCloudApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraCloudApi>(value),
    );
  }
}

String _$aleraCloudApiHash() => r'477927067ba52eb9008acde1e4d4fb3491a109ff';

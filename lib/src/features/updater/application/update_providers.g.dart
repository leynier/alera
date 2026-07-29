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
    r'39471705611dc7ed46547918ace9138b5dd92fbd';

/// The package manager that owns this installation, if any.
///
/// Read from the service so the detection stays in one place: the same value
/// decides whether an update may be auto-installed and what Settings offers.

@ProviderFor(packageManagerInstall)
final packageManagerInstallProvider = PackageManagerInstallProvider._();

/// The package manager that owns this installation, if any.
///
/// Read from the service so the detection stays in one place: the same value
/// decides whether an update may be auto-installed and what Settings offers.

final class PackageManagerInstallProvider
    extends
        $FunctionalProvider<
          PackageManagerInstall,
          PackageManagerInstall,
          PackageManagerInstall
        >
    with $Provider<PackageManagerInstall> {
  /// The package manager that owns this installation, if any.
  ///
  /// Read from the service so the detection stays in one place: the same value
  /// decides whether an update may be auto-installed and what Settings offers.
  PackageManagerInstallProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'packageManagerInstallProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$packageManagerInstallHash();

  @$internal
  @override
  $ProviderElement<PackageManagerInstall> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PackageManagerInstall create(Ref ref) {
    return packageManagerInstall(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PackageManagerInstall value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PackageManagerInstall>(value),
    );
  }
}

String _$packageManagerInstallHash() =>
    r'3d966f40da8258def2939eab16af39fbd53658b4';

/// Nothing reads this provider's value: mounting it is what starts the
/// recurring check, so the app shell watches it to keep it alive.

@ProviderFor(aleraUpdateCheckScheduler)
final aleraUpdateCheckSchedulerProvider = AleraUpdateCheckSchedulerProvider._();

/// Nothing reads this provider's value: mounting it is what starts the
/// recurring check, so the app shell watches it to keep it alive.

final class AleraUpdateCheckSchedulerProvider
    extends
        $FunctionalProvider<
          AleraUpdateCheckScheduler,
          AleraUpdateCheckScheduler,
          AleraUpdateCheckScheduler
        >
    with $Provider<AleraUpdateCheckScheduler> {
  /// Nothing reads this provider's value: mounting it is what starts the
  /// recurring check, so the app shell watches it to keep it alive.
  AleraUpdateCheckSchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraUpdateCheckSchedulerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraUpdateCheckSchedulerHash();

  @$internal
  @override
  $ProviderElement<AleraUpdateCheckScheduler> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AleraUpdateCheckScheduler create(Ref ref) {
    return aleraUpdateCheckScheduler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraUpdateCheckScheduler value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraUpdateCheckScheduler>(value),
    );
  }
}

String _$aleraUpdateCheckSchedulerHash() =>
    r'67849a95b31b03cd2cf69e09175d3ad56bfc89e5';

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_emulator_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileEmulatorService)
final mobileEmulatorServiceProvider = MobileEmulatorServiceProvider._();

final class MobileEmulatorServiceProvider
    extends
        $FunctionalProvider<
          MobileEmulatorService,
          MobileEmulatorService,
          MobileEmulatorService
        >
    with $Provider<MobileEmulatorService> {
  MobileEmulatorServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileEmulatorServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileEmulatorServiceHash();

  @$internal
  @override
  $ProviderElement<MobileEmulatorService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MobileEmulatorService create(Ref ref) {
    return mobileEmulatorService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileEmulatorService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileEmulatorService>(value),
    );
  }
}

String _$mobileEmulatorServiceHash() =>
    r'e8b2023004bc9fe34ac473ca8287106a64f5b91f';

@ProviderFor(mobileEmulatorLeaseCoordinator)
final mobileEmulatorLeaseCoordinatorProvider =
    MobileEmulatorLeaseCoordinatorProvider._();

final class MobileEmulatorLeaseCoordinatorProvider
    extends
        $FunctionalProvider<
          MobileEmulatorLeaseCoordinator,
          MobileEmulatorLeaseCoordinator,
          MobileEmulatorLeaseCoordinator
        >
    with $Provider<MobileEmulatorLeaseCoordinator> {
  MobileEmulatorLeaseCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileEmulatorLeaseCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileEmulatorLeaseCoordinatorHash();

  @$internal
  @override
  $ProviderElement<MobileEmulatorLeaseCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MobileEmulatorLeaseCoordinator create(Ref ref) {
    return mobileEmulatorLeaseCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileEmulatorLeaseCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileEmulatorLeaseCoordinator>(
        value,
      ),
    );
  }
}

String _$mobileEmulatorLeaseCoordinatorHash() =>
    r'8da601c775811c3fcdd9281493f79622fac55c05';

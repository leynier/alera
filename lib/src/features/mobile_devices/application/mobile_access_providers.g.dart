// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_access_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileAccessRepository)
final mobileAccessRepositoryProvider = MobileAccessRepositoryProvider._();

final class MobileAccessRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeMobileAccessRepository,
          RuntimeMobileAccessRepository,
          RuntimeMobileAccessRepository
        >
    with $Provider<RuntimeMobileAccessRepository> {
  MobileAccessRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileAccessRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileAccessRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeMobileAccessRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeMobileAccessRepository create(Ref ref) {
    return mobileAccessRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeMobileAccessRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeMobileAccessRepository>(
        value,
      ),
    );
  }
}

String _$mobileAccessRepositoryHash() =>
    r'40b2ea4f85f3c8fb08561e8deb1984dc8ca5f14f';

@ProviderFor(mobileAccessStatus)
final mobileAccessStatusProvider = MobileAccessStatusProvider._();

final class MobileAccessStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileAccessStatus>,
          MobileAccessStatus,
          Stream<MobileAccessStatus>
        >
    with
        $FutureModifier<MobileAccessStatus>,
        $StreamProvider<MobileAccessStatus> {
  MobileAccessStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileAccessStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileAccessStatusHash();

  @$internal
  @override
  $StreamProviderElement<MobileAccessStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<MobileAccessStatus> create(Ref ref) {
    return mobileAccessStatus(ref);
  }
}

String _$mobileAccessStatusHash() =>
    r'78ad52ac88057770a8304f1ba35ce6406add387f';

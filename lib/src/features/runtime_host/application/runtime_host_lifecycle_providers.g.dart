// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_host_lifecycle_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bundledSidecarVersionProbe)
final bundledSidecarVersionProbeProvider =
    BundledSidecarVersionProbeProvider._();

final class BundledSidecarVersionProbeProvider
    extends
        $FunctionalProvider<
          BundledSidecarVersionProbe,
          BundledSidecarVersionProbe,
          BundledSidecarVersionProbe
        >
    with $Provider<BundledSidecarVersionProbe> {
  BundledSidecarVersionProbeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bundledSidecarVersionProbeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bundledSidecarVersionProbeHash();

  @$internal
  @override
  $ProviderElement<BundledSidecarVersionProbe> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BundledSidecarVersionProbe create(Ref ref) {
    return bundledSidecarVersionProbe(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BundledSidecarVersionProbe value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BundledSidecarVersionProbe>(value),
    );
  }
}

String _$bundledSidecarVersionProbeHash() =>
    r'83977a1f5bfff07d2534ee4010220e3147d0d306';

@ProviderFor(runtimeHostLifecycleService)
final runtimeHostLifecycleServiceProvider =
    RuntimeHostLifecycleServiceProvider._();

final class RuntimeHostLifecycleServiceProvider
    extends
        $FunctionalProvider<
          RuntimeHostLifecycleService,
          RuntimeHostLifecycleService,
          RuntimeHostLifecycleService
        >
    with $Provider<RuntimeHostLifecycleService> {
  RuntimeHostLifecycleServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeHostLifecycleServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeHostLifecycleServiceHash();

  @$internal
  @override
  $ProviderElement<RuntimeHostLifecycleService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeHostLifecycleService create(Ref ref) {
    return runtimeHostLifecycleService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeHostLifecycleService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeHostLifecycleService>(value),
    );
  }
}

String _$runtimeHostLifecycleServiceHash() =>
    r'9c78d5059d3b6a0434e8ce942e9512ddebe4764a';

@ProviderFor(runtimeHostStatus)
final runtimeHostStatusProvider = RuntimeHostStatusProvider._();

final class RuntimeHostStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<RuntimeHostStatusSnapshot>,
          RuntimeHostStatusSnapshot,
          FutureOr<RuntimeHostStatusSnapshot>
        >
    with
        $FutureModifier<RuntimeHostStatusSnapshot>,
        $FutureProvider<RuntimeHostStatusSnapshot> {
  RuntimeHostStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeHostStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeHostStatusHash();

  @$internal
  @override
  $FutureProviderElement<RuntimeHostStatusSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RuntimeHostStatusSnapshot> create(Ref ref) {
    return runtimeHostStatus(ref);
  }
}

String _$runtimeHostStatusHash() => r'a44ba2341aed8ceae83e4f0133cda4a6202bce0e';

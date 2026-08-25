// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'keep_alive_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(keepAliveBackend)
final keepAliveBackendProvider = KeepAliveBackendProvider._();

final class KeepAliveBackendProvider
    extends
        $FunctionalProvider<
          KeepAliveBackend,
          KeepAliveBackend,
          KeepAliveBackend
        >
    with $Provider<KeepAliveBackend> {
  KeepAliveBackendProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keepAliveBackendProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keepAliveBackendHash();

  @$internal
  @override
  $ProviderElement<KeepAliveBackend> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KeepAliveBackend create(Ref ref) {
    return keepAliveBackend(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeepAliveBackend value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeepAliveBackend>(value),
    );
  }
}

String _$keepAliveBackendHash() => r'0193c079ddb837ccc46ecdbd80c555f3760c8b2a';

@ProviderFor(keepAliveService)
final keepAliveServiceProvider = KeepAliveServiceProvider._();

final class KeepAliveServiceProvider
    extends
        $FunctionalProvider<
          KeepAliveService,
          KeepAliveService,
          KeepAliveService
        >
    with $Provider<KeepAliveService> {
  KeepAliveServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keepAliveServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keepAliveServiceHash();

  @$internal
  @override
  $ProviderElement<KeepAliveService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KeepAliveService create(Ref ref) {
    return keepAliveService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeepAliveService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeepAliveService>(value),
    );
  }
}

String _$keepAliveServiceHash() => r'3d548bad5ad63dd3a38d03c15e71fd0ff9d744c2';

@ProviderFor(KeepAliveController)
final keepAliveControllerProvider = KeepAliveControllerProvider._();

final class KeepAliveControllerProvider
    extends $NotifierProvider<KeepAliveController, KeepAliveSnapshot> {
  KeepAliveControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keepAliveControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keepAliveControllerHash();

  @$internal
  @override
  KeepAliveController create() => KeepAliveController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeepAliveSnapshot value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeepAliveSnapshot>(value),
    );
  }
}

String _$keepAliveControllerHash() =>
    r'61787b87bd366469991deeb8ef7063924bfcb87a';

abstract class _$KeepAliveController extends $Notifier<KeepAliveSnapshot> {
  KeepAliveSnapshot build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<KeepAliveSnapshot, KeepAliveSnapshot>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<KeepAliveSnapshot, KeepAliveSnapshot>,
              KeepAliveSnapshot,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(keepAliveCoordinator)
final keepAliveCoordinatorProvider = KeepAliveCoordinatorProvider._();

final class KeepAliveCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  KeepAliveCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keepAliveCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keepAliveCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return keepAliveCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$keepAliveCoordinatorHash() =>
    r'f05a4276d1f9a6ae078c8580a677221734ae16d9';

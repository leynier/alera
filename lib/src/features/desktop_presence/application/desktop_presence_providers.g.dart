// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'desktop_presence_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(desktopPresenceBackend)
final desktopPresenceBackendProvider = DesktopPresenceBackendProvider._();

final class DesktopPresenceBackendProvider
    extends
        $FunctionalProvider<
          DesktopPresenceBackend,
          DesktopPresenceBackend,
          DesktopPresenceBackend
        >
    with $Provider<DesktopPresenceBackend> {
  DesktopPresenceBackendProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'desktopPresenceBackendProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$desktopPresenceBackendHash();

  @$internal
  @override
  $ProviderElement<DesktopPresenceBackend> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DesktopPresenceBackend create(Ref ref) {
    return desktopPresenceBackend(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DesktopPresenceBackend value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DesktopPresenceBackend>(value),
    );
  }
}

String _$desktopPresenceBackendHash() =>
    r'56fc4858ec39de0c53ad175a0724bb3ecbb5332b';

@ProviderFor(desktopPresenceCoordinator)
final desktopPresenceCoordinatorProvider =
    DesktopPresenceCoordinatorProvider._();

final class DesktopPresenceCoordinatorProvider
    extends
        $FunctionalProvider<
          DesktopPresenceCoordinator,
          DesktopPresenceCoordinator,
          DesktopPresenceCoordinator
        >
    with $Provider<DesktopPresenceCoordinator> {
  DesktopPresenceCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'desktopPresenceCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$desktopPresenceCoordinatorHash();

  @$internal
  @override
  $ProviderElement<DesktopPresenceCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DesktopPresenceCoordinator create(Ref ref) {
    return desktopPresenceCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DesktopPresenceCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DesktopPresenceCoordinator>(value),
    );
  }
}

String _$desktopPresenceCoordinatorHash() =>
    r'a32b4658226e232de8d8273c2d216012775efdfb';

/// Pushes tray visibility and the dock/taskbar badge whenever agent status or
/// the related settings change. No-op off desktop.

@ProviderFor(desktopPresenceSync)
final desktopPresenceSyncProvider = DesktopPresenceSyncProvider._();

/// Pushes tray visibility and the dock/taskbar badge whenever agent status or
/// the related settings change. No-op off desktop.

final class DesktopPresenceSyncProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Pushes tray visibility and the dock/taskbar badge whenever agent status or
  /// the related settings change. No-op off desktop.
  DesktopPresenceSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'desktopPresenceSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$desktopPresenceSyncHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return desktopPresenceSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$desktopPresenceSyncHash() =>
    r'6404976a76c4c09d554d3c72bd5bffd82f5af28b';

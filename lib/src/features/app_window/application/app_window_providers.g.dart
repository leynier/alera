// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_window_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appWindowStateRepository)
final appWindowStateRepositoryProvider = AppWindowStateRepositoryProvider._();

final class AppWindowStateRepositoryProvider
    extends
        $FunctionalProvider<
          AppWindowStateRepository,
          AppWindowStateRepository,
          AppWindowStateRepository
        >
    with $Provider<AppWindowStateRepository> {
  AppWindowStateRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appWindowStateRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appWindowStateRepositoryHash();

  @$internal
  @override
  $ProviderElement<AppWindowStateRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppWindowStateRepository create(Ref ref) {
    return appWindowStateRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppWindowStateRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppWindowStateRepository>(value),
    );
  }
}

String _$appWindowStateRepositoryHash() =>
    r'36ef08675cc02c3f054b790c2237a1d37b7433ff';

@ProviderFor(appWindowController)
final appWindowControllerProvider = AppWindowControllerProvider._();

final class AppWindowControllerProvider
    extends
        $FunctionalProvider<
          AppWindowController,
          AppWindowController,
          AppWindowController
        >
    with $Provider<AppWindowController> {
  AppWindowControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appWindowControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appWindowControllerHash();

  @$internal
  @override
  $ProviderElement<AppWindowController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppWindowController create(Ref ref) {
    return appWindowController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppWindowController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppWindowController>(value),
    );
  }
}

String _$appWindowControllerHash() =>
    r'45abcfc7aa17f08ef295e64eada14c4359672aa3';

@ProviderFor(appWindowDisplayProvider)
final appWindowDisplayProviderProvider = AppWindowDisplayProviderProvider._();

final class AppWindowDisplayProviderProvider
    extends
        $FunctionalProvider<
          AppWindowDisplayProvider,
          AppWindowDisplayProvider,
          AppWindowDisplayProvider
        >
    with $Provider<AppWindowDisplayProvider> {
  AppWindowDisplayProviderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appWindowDisplayProviderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appWindowDisplayProviderHash();

  @$internal
  @override
  $ProviderElement<AppWindowDisplayProvider> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppWindowDisplayProvider create(Ref ref) {
    return appWindowDisplayProvider(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppWindowDisplayProvider value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppWindowDisplayProvider>(value),
    );
  }
}

String _$appWindowDisplayProviderHash() =>
    r'6bfd2eaeeeadfda18264d76c1a6c6fa78b6994f0';

@ProviderFor(appWindowLifecycleCoordinator)
final appWindowLifecycleCoordinatorProvider =
    AppWindowLifecycleCoordinatorProvider._();

final class AppWindowLifecycleCoordinatorProvider
    extends
        $FunctionalProvider<
          AppWindowLifecycleCoordinator,
          AppWindowLifecycleCoordinator,
          AppWindowLifecycleCoordinator
        >
    with $Provider<AppWindowLifecycleCoordinator> {
  AppWindowLifecycleCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appWindowLifecycleCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appWindowLifecycleCoordinatorHash();

  @$internal
  @override
  $ProviderElement<AppWindowLifecycleCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppWindowLifecycleCoordinator create(Ref ref) {
    return appWindowLifecycleCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppWindowLifecycleCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppWindowLifecycleCoordinator>(
        value,
      ),
    );
  }
}

String _$appWindowLifecycleCoordinatorHash() =>
    r'cd701c2b5038caf5c56604db638e08dcc663e6c1';

/// Observes the app lifecycle so recurring work can park while nobody can see
/// its results.

@ProviderFor(appForeground)
final appForegroundProvider = AppForegroundProvider._();

/// Observes the app lifecycle so recurring work can park while nobody can see
/// its results.

final class AppForegroundProvider
    extends $FunctionalProvider<AppForeground, AppForeground, AppForeground>
    with $Provider<AppForeground> {
  /// Observes the app lifecycle so recurring work can park while nobody can see
  /// its results.
  AppForegroundProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appForegroundProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appForegroundHash();

  @$internal
  @override
  $ProviderElement<AppForeground> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppForeground create(Ref ref) {
    return appForeground(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppForeground value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppForeground>(value),
    );
  }
}

String _$appForegroundHash() => r'dceb40705264e2c77686d3c1eceb4b7a565bd934';

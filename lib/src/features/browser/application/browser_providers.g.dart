// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'browser_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(browserNativeCallbackCoordinator)
final browserNativeCallbackCoordinatorProvider =
    BrowserNativeCallbackCoordinatorProvider._();

final class BrowserNativeCallbackCoordinatorProvider
    extends
        $FunctionalProvider<
          BrowserNativeCallbackCoordinator,
          BrowserNativeCallbackCoordinator,
          BrowserNativeCallbackCoordinator
        >
    with $Provider<BrowserNativeCallbackCoordinator> {
  BrowserNativeCallbackCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserNativeCallbackCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserNativeCallbackCoordinatorHash();

  @$internal
  @override
  $ProviderElement<BrowserNativeCallbackCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserNativeCallbackCoordinator create(Ref ref) {
    return browserNativeCallbackCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserNativeCallbackCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserNativeCallbackCoordinator>(
        value,
      ),
    );
  }
}

String _$browserNativeCallbackCoordinatorHash() =>
    r'8051a776830e658320513cea0d4f1172f29079e9';

@ProviderFor(aleraBrowserClient)
final aleraBrowserClientProvider = AleraBrowserClientProvider._();

final class AleraBrowserClientProvider
    extends
        $FunctionalProvider<
          AleraBrowserClient,
          AleraBrowserClient,
          AleraBrowserClient
        >
    with $Provider<AleraBrowserClient> {
  AleraBrowserClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraBrowserClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraBrowserClientHash();

  @$internal
  @override
  $ProviderElement<AleraBrowserClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AleraBrowserClient create(Ref ref) {
    return aleraBrowserClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraBrowserClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraBrowserClient>(value),
    );
  }
}

String _$aleraBrowserClientHash() =>
    r'3a9e7926c48a20890b56b4a3e88369587940f896';

@ProviderFor(browserEngine)
final browserEngineProvider = BrowserEngineProvider._();

final class BrowserEngineProvider
    extends $FunctionalProvider<BrowserEngine, BrowserEngine, BrowserEngine>
    with $Provider<BrowserEngine> {
  BrowserEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserEngineHash();

  @$internal
  @override
  $ProviderElement<BrowserEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BrowserEngine create(Ref ref) {
    return browserEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserEngine>(value),
    );
  }
}

String _$browserEngineHash() => r'4f4d51783b592cbf10400e0e158f6cc5663df948';

@ProviderFor(browserAvailability)
final browserAvailabilityProvider = BrowserAvailabilityProvider._();

final class BrowserAvailabilityProvider
    extends
        $FunctionalProvider<
          AsyncValue<BrowserEngineCapabilities>,
          BrowserEngineCapabilities,
          FutureOr<BrowserEngineCapabilities>
        >
    with
        $FutureModifier<BrowserEngineCapabilities>,
        $FutureProvider<BrowserEngineCapabilities> {
  BrowserAvailabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserAvailabilityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserAvailabilityHash();

  @$internal
  @override
  $FutureProviderElement<BrowserEngineCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BrowserEngineCapabilities> create(Ref ref) {
    return browserAvailability(ref);
  }
}

String _$browserAvailabilityHash() =>
    r'04cd8346170ab37460cbe6e724778926551a9860';

@ProviderFor(browserSettingsService)
final browserSettingsServiceProvider = BrowserSettingsServiceProvider._();

final class BrowserSettingsServiceProvider
    extends
        $FunctionalProvider<
          BrowserSettingsService,
          BrowserSettingsService,
          BrowserSettingsService
        >
    with $Provider<BrowserSettingsService> {
  BrowserSettingsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserSettingsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserSettingsServiceHash();

  @$internal
  @override
  $ProviderElement<BrowserSettingsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserSettingsService create(Ref ref) {
    return browserSettingsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserSettingsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserSettingsService>(value),
    );
  }
}

String _$browserSettingsServiceHash() =>
    r'0c9e4cf90bdd04cc91f8a1f0b01c51728412a1da';

@ProviderFor(browserProfileService)
final browserProfileServiceProvider = BrowserProfileServiceProvider._();

final class BrowserProfileServiceProvider
    extends
        $FunctionalProvider<
          BrowserProfileService,
          BrowserProfileService,
          BrowserProfileService
        >
    with $Provider<BrowserProfileService> {
  BrowserProfileServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserProfileServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserProfileServiceHash();

  @$internal
  @override
  $ProviderElement<BrowserProfileService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserProfileService create(Ref ref) {
    return browserProfileService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserProfileService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserProfileService>(value),
    );
  }
}

String _$browserProfileServiceHash() =>
    r'03f707186e79b46821e7b16c8d3ead1ea009fffe';

@ProviderFor(browserHistoryService)
final browserHistoryServiceProvider = BrowserHistoryServiceProvider._();

final class BrowserHistoryServiceProvider
    extends
        $FunctionalProvider<
          BrowserHistoryService,
          BrowserHistoryService,
          BrowserHistoryService
        >
    with $Provider<BrowserHistoryService> {
  BrowserHistoryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserHistoryServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserHistoryServiceHash();

  @$internal
  @override
  $ProviderElement<BrowserHistoryService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserHistoryService create(Ref ref) {
    return browserHistoryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserHistoryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserHistoryService>(value),
    );
  }
}

String _$browserHistoryServiceHash() =>
    r'5fbc4af922283329f945153acdaa78c185329288';

@ProviderFor(browserPermissionService)
final browserPermissionServiceProvider = BrowserPermissionServiceProvider._();

final class BrowserPermissionServiceProvider
    extends
        $FunctionalProvider<
          BrowserPermissionService,
          BrowserPermissionService,
          BrowserPermissionService
        >
    with $Provider<BrowserPermissionService> {
  BrowserPermissionServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserPermissionServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserPermissionServiceHash();

  @$internal
  @override
  $ProviderElement<BrowserPermissionService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserPermissionService create(Ref ref) {
    return browserPermissionService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserPermissionService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserPermissionService>(value),
    );
  }
}

String _$browserPermissionServiceHash() =>
    r'22b1c2be33c049e8ec3db308930c1a2455822cca';

@ProviderFor(browserClosedTabsService)
final browserClosedTabsServiceProvider = BrowserClosedTabsServiceProvider._();

final class BrowserClosedTabsServiceProvider
    extends
        $FunctionalProvider<
          BrowserClosedTabsService,
          BrowserClosedTabsService,
          BrowserClosedTabsService
        >
    with $Provider<BrowserClosedTabsService> {
  BrowserClosedTabsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserClosedTabsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserClosedTabsServiceHash();

  @$internal
  @override
  $ProviderElement<BrowserClosedTabsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserClosedTabsService create(Ref ref) {
    return browserClosedTabsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserClosedTabsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserClosedTabsService>(value),
    );
  }
}

String _$browserClosedTabsServiceHash() =>
    r'7e56c718f64fc82f81921850ed141f2549a41ed4';

@ProviderFor(browserCertificateTrustService)
final browserCertificateTrustServiceProvider =
    BrowserCertificateTrustServiceProvider._();

final class BrowserCertificateTrustServiceProvider
    extends
        $FunctionalProvider<
          BrowserCertificateTrustService,
          BrowserCertificateTrustService,
          BrowserCertificateTrustService
        >
    with $Provider<BrowserCertificateTrustService> {
  BrowserCertificateTrustServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserCertificateTrustServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserCertificateTrustServiceHash();

  @$internal
  @override
  $ProviderElement<BrowserCertificateTrustService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserCertificateTrustService create(Ref ref) {
    return browserCertificateTrustService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserCertificateTrustService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserCertificateTrustService>(
        value,
      ),
    );
  }
}

String _$browserCertificateTrustServiceHash() =>
    r'6ff5d88f331e7cad884962805e2a92a3f59c02cc';

@ProviderFor(browserCertificateTrustRegistry)
final browserCertificateTrustRegistryProvider =
    BrowserCertificateTrustRegistryProvider._();

final class BrowserCertificateTrustRegistryProvider
    extends
        $FunctionalProvider<
          BrowserCertificateTrustRegistry,
          BrowserCertificateTrustRegistry,
          BrowserCertificateTrustRegistry
        >
    with $Provider<BrowserCertificateTrustRegistry> {
  BrowserCertificateTrustRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserCertificateTrustRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserCertificateTrustRegistryHash();

  @$internal
  @override
  $ProviderElement<BrowserCertificateTrustRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserCertificateTrustRegistry create(Ref ref) {
    return browserCertificateTrustRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserCertificateTrustRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserCertificateTrustRegistry>(
        value,
      ),
    );
  }
}

String _$browserCertificateTrustRegistryHash() =>
    r'8377cc04aaf0d47dedce7aeaac6314d3342f5b90';

@ProviderFor(browserProfileCoordinator)
final browserProfileCoordinatorProvider = BrowserProfileCoordinatorProvider._();

final class BrowserProfileCoordinatorProvider
    extends
        $FunctionalProvider<
          BrowserProfileCoordinator,
          BrowserProfileCoordinator,
          BrowserProfileCoordinator
        >
    with $Provider<BrowserProfileCoordinator> {
  BrowserProfileCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserProfileCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserProfileCoordinatorHash();

  @$internal
  @override
  $ProviderElement<BrowserProfileCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserProfileCoordinator create(Ref ref) {
    return browserProfileCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserProfileCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserProfileCoordinator>(value),
    );
  }
}

String _$browserProfileCoordinatorHash() =>
    r'415d6bd9eb95036dcd67092510d70863d356e7ca';

@ProviderFor(browserSessionRegistry)
final browserSessionRegistryProvider = BrowserSessionRegistryProvider._();

final class BrowserSessionRegistryProvider
    extends
        $FunctionalProvider<
          BrowserSessionRegistry,
          BrowserSessionRegistry,
          BrowserSessionRegistry
        >
    with $Provider<BrowserSessionRegistry> {
  BrowserSessionRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserSessionRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserSessionRegistryHash();

  @$internal
  @override
  $ProviderElement<BrowserSessionRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserSessionRegistry create(Ref ref) {
    return browserSessionRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserSessionRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserSessionRegistry>(value),
    );
  }
}

String _$browserSessionRegistryHash() =>
    r'55fd34100c0e477d737d5f38fb1b237d09a6d4d9';

@ProviderFor(browserPopupCoordinator)
final browserPopupCoordinatorProvider = BrowserPopupCoordinatorProvider._();

final class BrowserPopupCoordinatorProvider
    extends
        $FunctionalProvider<
          BrowserPopupCoordinator,
          BrowserPopupCoordinator,
          BrowserPopupCoordinator
        >
    with $Provider<BrowserPopupCoordinator> {
  BrowserPopupCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserPopupCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserPopupCoordinatorHash();

  @$internal
  @override
  $ProviderElement<BrowserPopupCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserPopupCoordinator create(Ref ref) {
    return browserPopupCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserPopupCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserPopupCoordinator>(value),
    );
  }
}

String _$browserPopupCoordinatorHash() =>
    r'ca5068f18a3b57c4c2dfa938598a1ba2132cbf8c';

@ProviderFor(browserRuntimeDriver)
final browserRuntimeDriverProvider = BrowserRuntimeDriverProvider._();

final class BrowserRuntimeDriverProvider
    extends
        $FunctionalProvider<
          BrowserRuntimeDriver,
          BrowserRuntimeDriver,
          BrowserRuntimeDriver
        >
    with $Provider<BrowserRuntimeDriver> {
  BrowserRuntimeDriverProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserRuntimeDriverProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserRuntimeDriverHash();

  @$internal
  @override
  $ProviderElement<BrowserRuntimeDriver> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserRuntimeDriver create(Ref ref) {
    return browserRuntimeDriver(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserRuntimeDriver value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserRuntimeDriver>(value),
    );
  }
}

String _$browserRuntimeDriverHash() =>
    r'6d9031fe37da8286cbbf6e0c210496df1dac8aaf';

@ProviderFor(browserEventDispatcher)
final browserEventDispatcherProvider = BrowserEventDispatcherProvider._();

final class BrowserEventDispatcherProvider
    extends
        $FunctionalProvider<
          BrowserRuntimeDriver,
          BrowserRuntimeDriver,
          BrowserRuntimeDriver
        >
    with $Provider<BrowserRuntimeDriver> {
  BrowserEventDispatcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserEventDispatcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserEventDispatcherHash();

  @$internal
  @override
  $ProviderElement<BrowserRuntimeDriver> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserRuntimeDriver create(Ref ref) {
    return browserEventDispatcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserRuntimeDriver value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserRuntimeDriver>(value),
    );
  }
}

String _$browserEventDispatcherHash() =>
    r'dedd105451b538a992ce2531bb285943a9c462e3';

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'configuration_sync_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(configurationSyncService)
final configurationSyncServiceProvider = ConfigurationSyncServiceProvider._();

final class ConfigurationSyncServiceProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConfigurationSyncService>,
          ConfigurationSyncService,
          FutureOr<ConfigurationSyncService>
        >
    with
        $FutureModifier<ConfigurationSyncService>,
        $FutureProvider<ConfigurationSyncService> {
  ConfigurationSyncServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'configurationSyncServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$configurationSyncServiceHash();

  @$internal
  @override
  $FutureProviderElement<ConfigurationSyncService> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ConfigurationSyncService> create(Ref ref) {
    return configurationSyncService(ref);
  }
}

String _$configurationSyncServiceHash() =>
    r'4f716cb785d13225fd61d0f46df150e49dd72354';

@ProviderFor(ConfigurationSyncController)
final configurationSyncControllerProvider =
    ConfigurationSyncControllerFamily._();

final class ConfigurationSyncControllerProvider
    extends
        $AsyncNotifierProvider<
          ConfigurationSyncController,
          ConfigurationScreenState
        > {
  ConfigurationSyncControllerProvider._({
    required ConfigurationSyncControllerFamily super.from,
    required ConfigurationSyncService super.argument,
  }) : super(
         retry: null,
         name: r'configurationSyncControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$configurationSyncControllerHash();

  @override
  String toString() {
    return r'configurationSyncControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ConfigurationSyncController create() => ConfigurationSyncController();

  @override
  bool operator ==(Object other) {
    return other is ConfigurationSyncControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$configurationSyncControllerHash() =>
    r'806bd0e1c2a1a69dc1541b412f492e462c6f9491';

final class ConfigurationSyncControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ConfigurationSyncController,
          AsyncValue<ConfigurationScreenState>,
          ConfigurationScreenState,
          FutureOr<ConfigurationScreenState>,
          ConfigurationSyncService
        > {
  ConfigurationSyncControllerFamily._()
    : super(
        retry: null,
        name: r'configurationSyncControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ConfigurationSyncControllerProvider call(ConfigurationSyncService service) =>
      ConfigurationSyncControllerProvider._(argument: service, from: this);

  @override
  String toString() => r'configurationSyncControllerProvider';
}

abstract class _$ConfigurationSyncController
    extends $AsyncNotifier<ConfigurationScreenState> {
  late final _$args = ref.$arg as ConfigurationSyncService;
  ConfigurationSyncService get service => _$args;

  FutureOr<ConfigurationScreenState> build(ConfigurationSyncService service);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<ConfigurationScreenState>,
              ConfigurationScreenState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ConfigurationScreenState>,
                ConfigurationScreenState
              >,
              AsyncValue<ConfigurationScreenState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

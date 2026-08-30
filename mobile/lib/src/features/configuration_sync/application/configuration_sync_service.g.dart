// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'configuration_sync_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ConfigurationSyncSelection)
final configurationSyncSelectionProvider =
    ConfigurationSyncSelectionProvider._();

final class ConfigurationSyncSelectionProvider
    extends
        $NotifierProvider<
          ConfigurationSyncSelection,
          ({String? accountId, String? hostId})
        > {
  ConfigurationSyncSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'configurationSyncSelectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$configurationSyncSelectionHash();

  @$internal
  @override
  ConfigurationSyncSelection create() => ConfigurationSyncSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({String? accountId, String? hostId}) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<({String? accountId, String? hostId})>(value),
    );
  }
}

String _$configurationSyncSelectionHash() =>
    r'16106dd7bb2425843e925e673b518bf24e0ddfb0';

abstract class _$ConfigurationSyncSelection
    extends $Notifier<({String? accountId, String? hostId})> {
  ({String? accountId, String? hostId}) build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              ({String? accountId, String? hostId}),
              ({String? accountId, String? hostId})
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ({String? accountId, String? hostId}),
                ({String? accountId, String? hostId})
              >,
              ({String? accountId, String? hostId}),
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(configurationSyncService)
final configurationSyncServiceProvider = ConfigurationSyncServiceFamily._();

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
  ConfigurationSyncServiceProvider._({
    required ConfigurationSyncServiceFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'configurationSyncServiceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$configurationSyncServiceHash();

  @override
  String toString() {
    return r'configurationSyncServiceProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<ConfigurationSyncService> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ConfigurationSyncService> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return configurationSyncService(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ConfigurationSyncServiceProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$configurationSyncServiceHash() =>
    r'4b8eb8eefa0c47853e2ecad5f4aa0fe6a260b24d';

final class ConfigurationSyncServiceFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<ConfigurationSyncService>,
          (String, String?)
        > {
  ConfigurationSyncServiceFamily._()
    : super(
        retry: null,
        name: r'configurationSyncServiceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ConfigurationSyncServiceProvider call(String accountId, String? hostId) =>
      ConfigurationSyncServiceProvider._(
        argument: (accountId, hostId),
        from: this,
      );

  @override
  String toString() => r'configurationSyncServiceProvider';
}

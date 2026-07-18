// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_accessory_layout_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(accessoryLayoutRepository)
final accessoryLayoutRepositoryProvider = AccessoryLayoutRepositoryProvider._();

final class AccessoryLayoutRepositoryProvider
    extends
        $FunctionalProvider<
          AccessoryLayoutRepository,
          AccessoryLayoutRepository,
          AccessoryLayoutRepository
        >
    with $Provider<AccessoryLayoutRepository> {
  AccessoryLayoutRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accessoryLayoutRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accessoryLayoutRepositoryHash();

  @$internal
  @override
  $ProviderElement<AccessoryLayoutRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AccessoryLayoutRepository create(Ref ref) {
    return accessoryLayoutRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccessoryLayoutRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccessoryLayoutRepository>(value),
    );
  }
}

String _$accessoryLayoutRepositoryHash() =>
    r'7768289d41251811c17a3f14cd77730c135e46fb';

/// The accessory bar configuration, global across hosts and tabs.

@ProviderFor(TerminalAccessoryLayoutController)
final terminalAccessoryLayoutControllerProvider =
    TerminalAccessoryLayoutControllerProvider._();

/// The accessory bar configuration, global across hosts and tabs.
final class TerminalAccessoryLayoutControllerProvider
    extends
        $AsyncNotifierProvider<
          TerminalAccessoryLayoutController,
          TerminalAccessoryLayout
        > {
  /// The accessory bar configuration, global across hosts and tabs.
  TerminalAccessoryLayoutControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalAccessoryLayoutControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$terminalAccessoryLayoutControllerHash();

  @$internal
  @override
  TerminalAccessoryLayoutController create() =>
      TerminalAccessoryLayoutController();
}

String _$terminalAccessoryLayoutControllerHash() =>
    r'92d2538042e283915e3b3289d642a57112877ee9';

/// The accessory bar configuration, global across hosts and tabs.

abstract class _$TerminalAccessoryLayoutController
    extends $AsyncNotifier<TerminalAccessoryLayout> {
  FutureOr<TerminalAccessoryLayout> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<TerminalAccessoryLayout>,
              TerminalAccessoryLayout
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<TerminalAccessoryLayout>,
                TerminalAccessoryLayout
              >,
              AsyncValue<TerminalAccessoryLayout>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

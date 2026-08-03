// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Indirection over the static pairing call so tests can drive the pairing
/// flow without a live runtime gateway.

@ProviderFor(pairDeviceFunction)
final pairDeviceFunctionProvider = PairDeviceFunctionProvider._();

/// Indirection over the static pairing call so tests can drive the pairing
/// flow without a live runtime gateway.

final class PairDeviceFunctionProvider
    extends
        $FunctionalProvider<
          PairDeviceFunction,
          PairDeviceFunction,
          PairDeviceFunction
        >
    with $Provider<PairDeviceFunction> {
  /// Indirection over the static pairing call so tests can drive the pairing
  /// flow without a live runtime gateway.
  PairDeviceFunctionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pairDeviceFunctionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pairDeviceFunctionHash();

  @$internal
  @override
  $ProviderElement<PairDeviceFunction> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PairDeviceFunction create(Ref ref) {
    return pairDeviceFunction(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PairDeviceFunction value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PairDeviceFunction>(value),
    );
  }
}

String _$pairDeviceFunctionHash() =>
    r'ce96aba4b6e7a4c64015590ec5655e2884619621';

/// Whether the QR scanner can be offered as the primary pairing input. Tests
/// (and platforms without camera support) override this to false so the
/// manual entry path becomes the primary flow.

@ProviderFor(pairingScannerEnabled)
final pairingScannerEnabledProvider = PairingScannerEnabledProvider._();

/// Whether the QR scanner can be offered as the primary pairing input. Tests
/// (and platforms without camera support) override this to false so the
/// manual entry path becomes the primary flow.

final class PairingScannerEnabledProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the QR scanner can be offered as the primary pairing input. Tests
  /// (and platforms without camera support) override this to false so the
  /// manual entry path becomes the primary flow.
  PairingScannerEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pairingScannerEnabledProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pairingScannerEnabledHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return pairingScannerEnabled(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$pairingScannerEnabledHash() =>
    r'2bbba5baa8d0e1ffe0f1eb5e8531be220f530cfb';

@ProviderFor(PairingController)
final pairingControllerProvider = PairingControllerProvider._();

final class PairingControllerProvider
    extends $NotifierProvider<PairingController, PairingFlowState> {
  PairingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pairingControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pairingControllerHash();

  @$internal
  @override
  PairingController create() => PairingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PairingFlowState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PairingFlowState>(value),
    );
  }
}

String _$pairingControllerHash() => r'03d72f3f3d29ac6c98b8356b218f026f593111b8';

abstract class _$PairingController extends $Notifier<PairingFlowState> {
  PairingFlowState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PairingFlowState, PairingFlowState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PairingFlowState, PairingFlowState>,
              PairingFlowState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

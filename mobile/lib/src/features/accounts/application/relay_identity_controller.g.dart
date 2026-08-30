// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relay_identity_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RelayIdentityController)
final relayIdentityControllerProvider = RelayIdentityControllerProvider._();

final class RelayIdentityControllerProvider
    extends $NotifierProvider<RelayIdentityController, void> {
  RelayIdentityControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relayIdentityControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relayIdentityControllerHash();

  @$internal
  @override
  RelayIdentityController create() => RelayIdentityController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$relayIdentityControllerHash() =>
    r'5940415f8e92416119da7a7fc695b8e2cea4680f';

abstract class _$RelayIdentityController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

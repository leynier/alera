// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AleraUpdateController)
final aleraUpdateControllerProvider = AleraUpdateControllerProvider._();

final class AleraUpdateControllerProvider
    extends $NotifierProvider<AleraUpdateController, AleraUpdateState> {
  AleraUpdateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraUpdateControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraUpdateControllerHash();

  @$internal
  @override
  AleraUpdateController create() => AleraUpdateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraUpdateState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraUpdateState>(value),
    );
  }
}

String _$aleraUpdateControllerHash() =>
    r'dedcc88375e9d7c5b601c8ea924ba65fbbc4c37d';

abstract class _$AleraUpdateController extends $Notifier<AleraUpdateState> {
  AleraUpdateState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AleraUpdateState, AleraUpdateState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AleraUpdateState, AleraUpdateState>,
              AleraUpdateState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

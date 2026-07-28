// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_push_intent_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PendingPushIntentController)
final pendingPushIntentControllerProvider =
    PendingPushIntentControllerProvider._();

final class PendingPushIntentControllerProvider
    extends
        $NotifierProvider<PendingPushIntentController, PushNavigationIntent?> {
  PendingPushIntentControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingPushIntentControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingPushIntentControllerHash();

  @$internal
  @override
  PendingPushIntentController create() => PendingPushIntentController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PushNavigationIntent? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PushNavigationIntent?>(value),
    );
  }
}

String _$pendingPushIntentControllerHash() =>
    r'f416d50b5807f52bf9b83a936cd5557bedb9e169';

abstract class _$PendingPushIntentController
    extends $Notifier<PushNavigationIntent?> {
  PushNavigationIntent? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PushNavigationIntent?, PushNavigationIntent?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PushNavigationIntent?, PushNavigationIntent?>,
              PushNavigationIntent?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

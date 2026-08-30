// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quota_host_visibility_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(QuotaHostVisibilityController)
final quotaHostVisibilityControllerProvider =
    QuotaHostVisibilityControllerProvider._();

final class QuotaHostVisibilityControllerProvider
    extends $AsyncNotifierProvider<QuotaHostVisibilityController, Set<String>> {
  QuotaHostVisibilityControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'quotaHostVisibilityControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$quotaHostVisibilityControllerHash();

  @$internal
  @override
  QuotaHostVisibilityController create() => QuotaHostVisibilityController();
}

String _$quotaHostVisibilityControllerHash() =>
    r'33addd4591b33f6337a74b4d1457e367af9b7359';

abstract class _$QuotaHostVisibilityController
    extends $AsyncNotifier<Set<String>> {
  FutureOr<Set<String>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Set<String>>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>>, Set<String>>,
              AsyncValue<Set<String>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

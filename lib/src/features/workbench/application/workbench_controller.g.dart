// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workbench_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkbenchController)
final workbenchControllerProvider = WorkbenchControllerProvider._();

final class WorkbenchControllerProvider
    extends $NotifierProvider<WorkbenchController, WorkbenchState> {
  WorkbenchControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workbenchControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workbenchControllerHash();

  @$internal
  @override
  WorkbenchController create() => WorkbenchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkbenchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkbenchState>(value),
    );
  }
}

String _$workbenchControllerHash() =>
    r'842a3b1fbd5628b0f11f83d26f2d89f966f7ae52';

abstract class _$WorkbenchController extends $Notifier<WorkbenchState> {
  WorkbenchState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<WorkbenchState, WorkbenchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkbenchState, WorkbenchState>,
              WorkbenchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

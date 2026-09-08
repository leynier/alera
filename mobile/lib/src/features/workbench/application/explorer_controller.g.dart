// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explorer_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ExplorerController)
final explorerControllerProvider = ExplorerControllerFamily._();

final class ExplorerControllerProvider
    extends $AsyncNotifierProvider<ExplorerController, ExplorerViewState> {
  ExplorerControllerProvider._({
    required ExplorerControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'explorerControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$explorerControllerHash();

  @override
  String toString() {
    return r'explorerControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ExplorerController create() => ExplorerController();

  @override
  bool operator ==(Object other) {
    return other is ExplorerControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$explorerControllerHash() =>
    r'c54a65ce49110a6664d4082092a6e7094ba09f0f';

final class ExplorerControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ExplorerController,
          AsyncValue<ExplorerViewState>,
          ExplorerViewState,
          FutureOr<ExplorerViewState>,
          (String, String)
        > {
  ExplorerControllerFamily._()
    : super(
        retry: null,
        name: r'explorerControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ExplorerControllerProvider call(String hostId, String workspaceId) =>
      ExplorerControllerProvider._(argument: (hostId, workspaceId), from: this);

  @override
  String toString() => r'explorerControllerProvider';
}

abstract class _$ExplorerController extends $AsyncNotifier<ExplorerViewState> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  FutureOr<ExplorerViewState> build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ExplorerViewState>, ExplorerViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ExplorerViewState>, ExplorerViewState>,
              AsyncValue<ExplorerViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

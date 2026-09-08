// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_text_search_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceTextSearchController)
final workspaceTextSearchControllerProvider =
    WorkspaceTextSearchControllerFamily._();

final class WorkspaceTextSearchControllerProvider
    extends
        $NotifierProvider<
          WorkspaceTextSearchController,
          WorkspaceTextSearchState
        > {
  WorkspaceTextSearchControllerProvider._({
    required WorkspaceTextSearchControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'workspaceTextSearchControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceTextSearchControllerHash();

  @override
  String toString() {
    return r'workspaceTextSearchControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  WorkspaceTextSearchController create() => WorkspaceTextSearchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceTextSearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceTextSearchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceTextSearchControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceTextSearchControllerHash() =>
    r'cd48d3e45216c1eafccd941026d3de7d1f90e889';

final class WorkspaceTextSearchControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceTextSearchController,
          WorkspaceTextSearchState,
          WorkspaceTextSearchState,
          WorkspaceTextSearchState,
          (String, String)
        > {
  WorkspaceTextSearchControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceTextSearchControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceTextSearchControllerProvider call(
    String hostId,
    String workspaceId,
  ) => WorkspaceTextSearchControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'workspaceTextSearchControllerProvider';
}

abstract class _$WorkspaceTextSearchController
    extends $Notifier<WorkspaceTextSearchState> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  WorkspaceTextSearchState build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<WorkspaceTextSearchState, WorkspaceTextSearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkspaceTextSearchState, WorkspaceTextSearchState>,
              WorkspaceTextSearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

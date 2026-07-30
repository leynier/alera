// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_search_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceSearchController)
final workspaceSearchControllerProvider = WorkspaceSearchControllerFamily._();

final class WorkspaceSearchControllerProvider
    extends $NotifierProvider<WorkspaceSearchController, WorkspaceSearchState> {
  WorkspaceSearchControllerProvider._({
    required WorkspaceSearchControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceSearchControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceSearchControllerHash();

  @override
  String toString() {
    return r'workspaceSearchControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceSearchController create() => WorkspaceSearchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceSearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceSearchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceSearchControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceSearchControllerHash() =>
    r'4d02d29c1e7d2a865e098d0e1e93b03fc49dfdd5';

final class WorkspaceSearchControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceSearchController,
          WorkspaceSearchState,
          WorkspaceSearchState,
          WorkspaceSearchState,
          String
        > {
  WorkspaceSearchControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceSearchControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  WorkspaceSearchControllerProvider call(String workspaceId) =>
      WorkspaceSearchControllerProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'workspaceSearchControllerProvider';
}

abstract class _$WorkspaceSearchController
    extends $Notifier<WorkspaceSearchState> {
  late final _$args = ref.$arg as String;
  String get workspaceId => _$args;

  WorkspaceSearchState build(String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<WorkspaceSearchState, WorkspaceSearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkspaceSearchState, WorkspaceSearchState>,
              WorkspaceSearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceListController)
final workspaceListControllerProvider = WorkspaceListControllerFamily._();

final class WorkspaceListControllerProvider
    extends $AsyncNotifierProvider<WorkspaceListController, WorkspaceListData> {
  WorkspaceListControllerProvider._({
    required WorkspaceListControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceListControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceListControllerHash();

  @override
  String toString() {
    return r'workspaceListControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceListController create() => WorkspaceListController();

  @override
  bool operator ==(Object other) {
    return other is WorkspaceListControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceListControllerHash() =>
    r'5b414688e1494340d13c8eac099b7c0e890049d2';

final class WorkspaceListControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceListController,
          AsyncValue<WorkspaceListData>,
          WorkspaceListData,
          FutureOr<WorkspaceListData>,
          String
        > {
  WorkspaceListControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceListControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceListControllerProvider call(String hostId) =>
      WorkspaceListControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'workspaceListControllerProvider';
}

abstract class _$WorkspaceListController
    extends $AsyncNotifier<WorkspaceListData> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<WorkspaceListData> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<WorkspaceListData>, WorkspaceListData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<WorkspaceListData>, WorkspaceListData>,
              AsyncValue<WorkspaceListData>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

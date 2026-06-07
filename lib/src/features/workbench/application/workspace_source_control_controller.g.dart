// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_source_control_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceSourceControlController)
final workspaceSourceControlControllerProvider =
    WorkspaceSourceControlControllerFamily._();

final class WorkspaceSourceControlControllerProvider
    extends
        $AsyncNotifierProvider<
          WorkspaceSourceControlController,
          WorkspaceSourceControlState
        > {
  WorkspaceSourceControlControllerProvider._({
    required WorkspaceSourceControlControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceSourceControlControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceSourceControlControllerHash();

  @override
  String toString() {
    return r'workspaceSourceControlControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceSourceControlController create() =>
      WorkspaceSourceControlController();

  @override
  bool operator ==(Object other) {
    return other is WorkspaceSourceControlControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceSourceControlControllerHash() =>
    r'd67f09b5830696c917a29fd27831cb43d861a2cd';

final class WorkspaceSourceControlControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceSourceControlController,
          AsyncValue<WorkspaceSourceControlState>,
          WorkspaceSourceControlState,
          FutureOr<WorkspaceSourceControlState>,
          String
        > {
  WorkspaceSourceControlControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceSourceControlControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceSourceControlControllerProvider call(String workspacePath) =>
      WorkspaceSourceControlControllerProvider._(
        argument: workspacePath,
        from: this,
      );

  @override
  String toString() => r'workspaceSourceControlControllerProvider';
}

abstract class _$WorkspaceSourceControlController
    extends $AsyncNotifier<WorkspaceSourceControlState> {
  late final _$args = ref.$arg as String;
  String get workspacePath => _$args;

  FutureOr<WorkspaceSourceControlState> build(String workspacePath);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<WorkspaceSourceControlState>,
              WorkspaceSourceControlState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<WorkspaceSourceControlState>,
                WorkspaceSourceControlState
              >,
              AsyncValue<WorkspaceSourceControlState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

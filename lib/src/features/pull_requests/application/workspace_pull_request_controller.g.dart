// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_pull_request_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspacePullRequestController)
final workspacePullRequestControllerProvider =
    WorkspacePullRequestControllerFamily._();

final class WorkspacePullRequestControllerProvider
    extends
        $AsyncNotifierProvider<
          WorkspacePullRequestController,
          WorkspacePullRequestState
        > {
  WorkspacePullRequestControllerProvider._({
    required WorkspacePullRequestControllerFamily super.from,
    required WorkspacePullRequestScope super.argument,
  }) : super(
         retry: null,
         name: r'workspacePullRequestControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspacePullRequestControllerHash();

  @override
  String toString() {
    return r'workspacePullRequestControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspacePullRequestController create() => WorkspacePullRequestController();

  @override
  bool operator ==(Object other) {
    return other is WorkspacePullRequestControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspacePullRequestControllerHash() =>
    r'eac4ab88a727ac219c2c1f79fa6f164c2fc4ce3d';

final class WorkspacePullRequestControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspacePullRequestController,
          AsyncValue<WorkspacePullRequestState>,
          WorkspacePullRequestState,
          FutureOr<WorkspacePullRequestState>,
          WorkspacePullRequestScope
        > {
  WorkspacePullRequestControllerFamily._()
    : super(
        retry: null,
        name: r'workspacePullRequestControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  WorkspacePullRequestControllerProvider call(
    WorkspacePullRequestScope scope,
  ) => WorkspacePullRequestControllerProvider._(argument: scope, from: this);

  @override
  String toString() => r'workspacePullRequestControllerProvider';
}

abstract class _$WorkspacePullRequestController
    extends $AsyncNotifier<WorkspacePullRequestState> {
  late final _$args = ref.$arg as WorkspacePullRequestScope;
  WorkspacePullRequestScope get scope => _$args;

  FutureOr<WorkspacePullRequestState> build(WorkspacePullRequestScope scope);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<WorkspacePullRequestState>,
              WorkspacePullRequestState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<WorkspacePullRequestState>,
                WorkspacePullRequestState
              >,
              AsyncValue<WorkspacePullRequestState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

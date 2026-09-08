// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_agent_comment_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceAgentCommentController)
final workspaceAgentCommentControllerProvider =
    WorkspaceAgentCommentControllerFamily._();

final class WorkspaceAgentCommentControllerProvider
    extends
        $NotifierProvider<
          WorkspaceAgentCommentController,
          List<WorkspaceAgentComment>
        > {
  WorkspaceAgentCommentControllerProvider._({
    required WorkspaceAgentCommentControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceAgentCommentControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceAgentCommentControllerHash();

  @override
  String toString() {
    return r'workspaceAgentCommentControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceAgentCommentController create() => WorkspaceAgentCommentController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<WorkspaceAgentComment> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<WorkspaceAgentComment>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceAgentCommentControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceAgentCommentControllerHash() =>
    r'06cc16e82101b64216c3b8c2972727b1cc388570';

final class WorkspaceAgentCommentControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceAgentCommentController,
          List<WorkspaceAgentComment>,
          List<WorkspaceAgentComment>,
          List<WorkspaceAgentComment>,
          String
        > {
  WorkspaceAgentCommentControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceAgentCommentControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  WorkspaceAgentCommentControllerProvider call(String workspaceId) =>
      WorkspaceAgentCommentControllerProvider._(
        argument: workspaceId,
        from: this,
      );

  @override
  String toString() => r'workspaceAgentCommentControllerProvider';
}

abstract class _$WorkspaceAgentCommentController
    extends $Notifier<List<WorkspaceAgentComment>> {
  late final _$args = ref.$arg as String;
  String get workspaceId => _$args;

  List<WorkspaceAgentComment> build(String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<List<WorkspaceAgentComment>, List<WorkspaceAgentComment>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                List<WorkspaceAgentComment>,
                List<WorkspaceAgentComment>
              >,
              List<WorkspaceAgentComment>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

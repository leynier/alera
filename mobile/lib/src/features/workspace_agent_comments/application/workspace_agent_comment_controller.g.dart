// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_agent_comment_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Draft file comments for one workspace, held in memory like the desktop
/// queue. `keepAlive` so switching panels does not discard them.

@ProviderFor(WorkspaceAgentCommentController)
final workspaceAgentCommentControllerProvider =
    WorkspaceAgentCommentControllerFamily._();

/// Draft file comments for one workspace, held in memory like the desktop
/// queue. `keepAlive` so switching panels does not discard them.
final class WorkspaceAgentCommentControllerProvider
    extends
        $NotifierProvider<
          WorkspaceAgentCommentController,
          List<WorkspaceAgentComment>
        > {
  /// Draft file comments for one workspace, held in memory like the desktop
  /// queue. `keepAlive` so switching panels does not discard them.
  WorkspaceAgentCommentControllerProvider._({
    required WorkspaceAgentCommentControllerFamily super.from,
    required (String, String) super.argument,
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
        '$argument';
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
    r'26e6e45f6fbd1f4615092418f9f5b51c157750db';

/// Draft file comments for one workspace, held in memory like the desktop
/// queue. `keepAlive` so switching panels does not discard them.

final class WorkspaceAgentCommentControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceAgentCommentController,
          List<WorkspaceAgentComment>,
          List<WorkspaceAgentComment>,
          List<WorkspaceAgentComment>,
          (String, String)
        > {
  WorkspaceAgentCommentControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceAgentCommentControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Draft file comments for one workspace, held in memory like the desktop
  /// queue. `keepAlive` so switching panels does not discard them.

  WorkspaceAgentCommentControllerProvider call(
    String hostId,
    String workspaceId,
  ) => WorkspaceAgentCommentControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'workspaceAgentCommentControllerProvider';
}

/// Draft file comments for one workspace, held in memory like the desktop
/// queue. `keepAlive` so switching panels does not discard them.

abstract class _$WorkspaceAgentCommentController
    extends $Notifier<List<WorkspaceAgentComment>> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  List<WorkspaceAgentComment> build(String hostId, String workspaceId);
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
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

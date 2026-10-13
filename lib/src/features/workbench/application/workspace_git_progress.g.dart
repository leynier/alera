// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_git_progress.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceGitProgress)
final workspaceGitProgressProvider = WorkspaceGitProgressFamily._();

final class WorkspaceGitProgressProvider
    extends
        $NotifierProvider<WorkspaceGitProgress, WorkspaceGitProgressState?> {
  WorkspaceGitProgressProvider._({
    required WorkspaceGitProgressFamily super.from,
    required WorkspacePullRequestScope super.argument,
  }) : super(
         retry: null,
         name: r'workspaceGitProgressProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceGitProgressHash();

  @override
  String toString() {
    return r'workspaceGitProgressProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceGitProgress create() => WorkspaceGitProgress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceGitProgressState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceGitProgressState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceGitProgressProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceGitProgressHash() =>
    r'12ac36b4666e8cbeb93aafac50544f27ac25102c';

final class WorkspaceGitProgressFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceGitProgress,
          WorkspaceGitProgressState?,
          WorkspaceGitProgressState?,
          WorkspaceGitProgressState?,
          WorkspacePullRequestScope
        > {
  WorkspaceGitProgressFamily._()
    : super(
        retry: null,
        name: r'workspaceGitProgressProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  WorkspaceGitProgressProvider call(WorkspacePullRequestScope scope) =>
      WorkspaceGitProgressProvider._(argument: scope, from: this);

  @override
  String toString() => r'workspaceGitProgressProvider';
}

abstract class _$WorkspaceGitProgress
    extends $Notifier<WorkspaceGitProgressState?> {
  late final _$args = ref.$arg as WorkspacePullRequestScope;
  WorkspacePullRequestScope get scope => _$args;

  WorkspaceGitProgressState? build(WorkspacePullRequestScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<WorkspaceGitProgressState?, WorkspaceGitProgressState?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                WorkspaceGitProgressState?,
                WorkspaceGitProgressState?
              >,
              WorkspaceGitProgressState?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

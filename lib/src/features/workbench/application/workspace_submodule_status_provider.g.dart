// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_submodule_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspaceSubmoduleStatus)
final workspaceSubmoduleStatusProvider = WorkspaceSubmoduleStatusFamily._();

final class WorkspaceSubmoduleStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<GitStatusResult>,
          GitStatusResult,
          FutureOr<GitStatusResult>
        >
    with $FutureModifier<GitStatusResult>, $FutureProvider<GitStatusResult> {
  WorkspaceSubmoduleStatusProvider._({
    required WorkspaceSubmoduleStatusFamily super.from,
    required ({String workspacePath, String submodulePath, GitChangeArea area})
    super.argument,
  }) : super(
         retry: null,
         name: r'workspaceSubmoduleStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceSubmoduleStatusHash();

  @override
  String toString() {
    return r'workspaceSubmoduleStatusProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<GitStatusResult> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GitStatusResult> create(Ref ref) {
    final argument =
        this.argument
            as ({
              String workspacePath,
              String submodulePath,
              GitChangeArea area,
            });
    return workspaceSubmoduleStatus(
      ref,
      workspacePath: argument.workspacePath,
      submodulePath: argument.submodulePath,
      area: argument.area,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceSubmoduleStatusProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceSubmoduleStatusHash() =>
    r'96d9fa9820a539818ef99d60699efe64e31aa9b5';

final class WorkspaceSubmoduleStatusFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<GitStatusResult>,
          ({String workspacePath, String submodulePath, GitChangeArea area})
        > {
  WorkspaceSubmoduleStatusFamily._()
    : super(
        retry: null,
        name: r'workspaceSubmoduleStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceSubmoduleStatusProvider call({
    required String workspacePath,
    required String submodulePath,
    required GitChangeArea area,
  }) => WorkspaceSubmoduleStatusProvider._(
    argument: (
      workspacePath: workspacePath,
      submodulePath: submodulePath,
      area: area,
    ),
    from: this,
  );

  @override
  String toString() => r'workspaceSubmoduleStatusProvider';
}

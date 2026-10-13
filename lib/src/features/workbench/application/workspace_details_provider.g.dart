// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_details_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspaceDetails)
final workspaceDetailsProvider = WorkspaceDetailsFamily._();

final class WorkspaceDetailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<WorkspaceDetailsState>,
          WorkspaceDetailsState,
          FutureOr<WorkspaceDetailsState>
        >
    with
        $FutureModifier<WorkspaceDetailsState>,
        $FutureProvider<WorkspaceDetailsState> {
  WorkspaceDetailsProvider._({
    required WorkspaceDetailsFamily super.from,
    required WorkspacePullRequestScope super.argument,
  }) : super(
         retry: null,
         name: r'workspaceDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceDetailsHash();

  @override
  String toString() {
    return r'workspaceDetailsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<WorkspaceDetailsState> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<WorkspaceDetailsState> create(Ref ref) {
    final argument = this.argument as WorkspacePullRequestScope;
    return workspaceDetails(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceDetailsHash() => r'acd8e18540b9c4b2884843f3b5b840ea7a2e13f1';

final class WorkspaceDetailsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<WorkspaceDetailsState>,
          WorkspacePullRequestScope
        > {
  WorkspaceDetailsFamily._()
    : super(
        retry: null,
        name: r'workspaceDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceDetailsProvider call(WorkspacePullRequestScope scope) =>
      WorkspaceDetailsProvider._(argument: scope, from: this);

  @override
  String toString() => r'workspaceDetailsProvider';
}

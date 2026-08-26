// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_explorer_reveal.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceExplorerRevealController)
final workspaceExplorerRevealControllerProvider =
    WorkspaceExplorerRevealControllerProvider._();

final class WorkspaceExplorerRevealControllerProvider
    extends
        $NotifierProvider<
          WorkspaceExplorerRevealController,
          WorkspaceExplorerRevealRequest?
        > {
  WorkspaceExplorerRevealControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceExplorerRevealControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspaceExplorerRevealControllerHash();

  @$internal
  @override
  WorkspaceExplorerRevealController create() =>
      WorkspaceExplorerRevealController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceExplorerRevealRequest? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceExplorerRevealRequest?>(
        value,
      ),
    );
  }
}

String _$workspaceExplorerRevealControllerHash() =>
    r'd4f06706cfb7bbbdcd32e1f7dc53f9dd2241e1da';

abstract class _$WorkspaceExplorerRevealController
    extends $Notifier<WorkspaceExplorerRevealRequest?> {
  WorkspaceExplorerRevealRequest? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              WorkspaceExplorerRevealRequest?,
              WorkspaceExplorerRevealRequest?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                WorkspaceExplorerRevealRequest?,
                WorkspaceExplorerRevealRequest?
              >,
              WorkspaceExplorerRevealRequest?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

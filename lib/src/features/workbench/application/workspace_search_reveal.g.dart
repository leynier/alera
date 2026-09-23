// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_search_reveal.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceSearchReveal)
final workspaceSearchRevealProvider = WorkspaceSearchRevealProvider._();

final class WorkspaceSearchRevealProvider
    extends
        $NotifierProvider<
          WorkspaceSearchReveal,
          WorkspaceSearchRevealRequest?
        > {
  WorkspaceSearchRevealProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceSearchRevealProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceSearchRevealHash();

  @$internal
  @override
  WorkspaceSearchReveal create() => WorkspaceSearchReveal();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceSearchRevealRequest? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceSearchRevealRequest?>(
        value,
      ),
    );
  }
}

String _$workspaceSearchRevealHash() =>
    r'8c6a0755b7d960137be5c869a9db7d241618d032';

abstract class _$WorkspaceSearchReveal
    extends $Notifier<WorkspaceSearchRevealRequest?> {
  WorkspaceSearchRevealRequest? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              WorkspaceSearchRevealRequest?,
              WorkspaceSearchRevealRequest?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                WorkspaceSearchRevealRequest?,
                WorkspaceSearchRevealRequest?
              >,
              WorkspaceSearchRevealRequest?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

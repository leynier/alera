// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_pull_request_refresh_signal.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Lightweight invalidation signal shared by PR mutations and the global
/// sidebar monitor. Reading this provider never initializes settings, storage,
/// git, or forge dependencies.

@ProviderFor(WorkspacePullRequestRefreshSignal)
final workspacePullRequestRefreshSignalProvider =
    WorkspacePullRequestRefreshSignalProvider._();

/// Lightweight invalidation signal shared by PR mutations and the global
/// sidebar monitor. Reading this provider never initializes settings, storage,
/// git, or forge dependencies.
final class WorkspacePullRequestRefreshSignalProvider
    extends $NotifierProvider<WorkspacePullRequestRefreshSignal, int> {
  /// Lightweight invalidation signal shared by PR mutations and the global
  /// sidebar monitor. Reading this provider never initializes settings, storage,
  /// git, or forge dependencies.
  WorkspacePullRequestRefreshSignalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspacePullRequestRefreshSignalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspacePullRequestRefreshSignalHash();

  @$internal
  @override
  WorkspacePullRequestRefreshSignal create() =>
      WorkspacePullRequestRefreshSignal();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$workspacePullRequestRefreshSignalHash() =>
    r'867695d764da709de59a83a3caba8ec9ab61b7fc';

/// Lightweight invalidation signal shared by PR mutations and the global
/// sidebar monitor. Reading this provider never initializes settings, storage,
/// git, or forge dependencies.

abstract class _$WorkspacePullRequestRefreshSignal extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

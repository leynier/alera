// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_activity_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracks the last discrete activity timestamp per workspace (agent state
/// transitions, terminal lifecycle) and persists it with a debounce. State is
/// the in-memory map used by the Agent Activity sort as its recency fallback.

@ProviderFor(WorkspaceActivityController)
final workspaceActivityControllerProvider =
    WorkspaceActivityControllerProvider._();

/// Tracks the last discrete activity timestamp per workspace (agent state
/// transitions, terminal lifecycle) and persists it with a debounce. State is
/// the in-memory map used by the Agent Activity sort as its recency fallback.
final class WorkspaceActivityControllerProvider
    extends
        $NotifierProvider<WorkspaceActivityController, Map<String, DateTime>> {
  /// Tracks the last discrete activity timestamp per workspace (agent state
  /// transitions, terminal lifecycle) and persists it with a debounce. State is
  /// the in-memory map used by the Agent Activity sort as its recency fallback.
  WorkspaceActivityControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceActivityControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceActivityControllerHash();

  @$internal
  @override
  WorkspaceActivityController create() => WorkspaceActivityController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, DateTime> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, DateTime>>(value),
    );
  }
}

String _$workspaceActivityControllerHash() =>
    r'a0733e981dd5ae0a369cd370aa6c86db837ff4ef';

/// Tracks the last discrete activity timestamp per workspace (agent state
/// transitions, terminal lifecycle) and persists it with a debounce. State is
/// the in-memory map used by the Agent Activity sort as its recency fallback.

abstract class _$WorkspaceActivityController
    extends $Notifier<Map<String, DateTime>> {
  Map<String, DateTime> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Map<String, DateTime>, Map<String, DateTime>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, DateTime>, Map<String, DateTime>>,
              Map<String, DateTime>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Feeds [WorkspaceActivityController] from discrete agent status transitions.
/// Tool-by-tool updates within one state do not count as activity - only a
/// `state`/`stateStartedAt` change marks the workspace as active.

@ProviderFor(workspaceActivityCoordinator)
final workspaceActivityCoordinatorProvider =
    WorkspaceActivityCoordinatorProvider._();

/// Feeds [WorkspaceActivityController] from discrete agent status transitions.
/// Tool-by-tool updates within one state do not count as activity - only a
/// `state`/`stateStartedAt` change marks the workspace as active.

final class WorkspaceActivityCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Feeds [WorkspaceActivityController] from discrete agent status transitions.
  /// Tool-by-tool updates within one state do not count as activity - only a
  /// `state`/`stateStartedAt` change marks the workspace as active.
  WorkspaceActivityCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceActivityCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceActivityCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return workspaceActivityCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$workspaceActivityCoordinatorHash() =>
    r'dc943e73259eb13cd704e5e552c2fbb6b6a6f867';

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workbench_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workbenchRepository)
final workbenchRepositoryProvider = WorkbenchRepositoryProvider._();

final class WorkbenchRepositoryProvider
    extends
        $FunctionalProvider<
          WorkbenchRepository,
          WorkbenchRepository,
          WorkbenchRepository
        >
    with $Provider<WorkbenchRepository> {
  WorkbenchRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workbenchRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workbenchRepositoryHash();

  @$internal
  @override
  $ProviderElement<WorkbenchRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkbenchRepository create(Ref ref) {
    return workbenchRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkbenchRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkbenchRepository>(value),
    );
  }
}

String _$workbenchRepositoryHash() =>
    r'8c1302e94b473115830f6b43e487e1a2d8b87156';

@ProviderFor(workspaceGraphRepository)
final workspaceGraphRepositoryProvider = WorkspaceGraphRepositoryProvider._();

final class WorkspaceGraphRepositoryProvider
    extends
        $FunctionalProvider<
          WorkspaceGraphRepository,
          WorkspaceGraphRepository,
          WorkspaceGraphRepository
        >
    with $Provider<WorkspaceGraphRepository> {
  WorkspaceGraphRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceGraphRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceGraphRepositoryHash();

  @$internal
  @override
  $ProviderElement<WorkspaceGraphRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceGraphRepository create(Ref ref) {
    return workspaceGraphRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceGraphRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceGraphRepository>(value),
    );
  }
}

String _$workspaceGraphRepositoryHash() =>
    r'4e7ca75e44454275b59debc04b7de0f1123353ce';

@ProviderFor(workbenchViewPrefsRepository)
final workbenchViewPrefsRepositoryProvider =
    WorkbenchViewPrefsRepositoryProvider._();

final class WorkbenchViewPrefsRepositoryProvider
    extends
        $FunctionalProvider<
          WorkbenchViewPrefsRepository,
          WorkbenchViewPrefsRepository,
          WorkbenchViewPrefsRepository
        >
    with $Provider<WorkbenchViewPrefsRepository> {
  WorkbenchViewPrefsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workbenchViewPrefsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workbenchViewPrefsRepositoryHash();

  @$internal
  @override
  $ProviderElement<WorkbenchViewPrefsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkbenchViewPrefsRepository create(Ref ref) {
    return workbenchViewPrefsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkbenchViewPrefsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkbenchViewPrefsRepository>(value),
    );
  }
}

String _$workbenchViewPrefsRepositoryHash() =>
    r'307cb46e7f48379a186243cc2863d6f89141eebc';

@ProviderFor(sidebarOrderMemory)
final sidebarOrderMemoryProvider = SidebarOrderMemoryProvider._();

final class SidebarOrderMemoryProvider
    extends
        $FunctionalProvider<
          SidebarOrderMemory,
          SidebarOrderMemory,
          SidebarOrderMemory
        >
    with $Provider<SidebarOrderMemory> {
  SidebarOrderMemoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sidebarOrderMemoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sidebarOrderMemoryHash();

  @$internal
  @override
  $ProviderElement<SidebarOrderMemory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SidebarOrderMemory create(Ref ref) {
    return sidebarOrderMemory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SidebarOrderMemory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SidebarOrderMemory>(value),
    );
  }
}

String _$sidebarOrderMemoryHash() =>
    r'63af5266267a090aad55563c87262c6ea27d6a5b';

/// The sidebar row list, recomputed once per state change instead of once per
/// widget rebuild.
///
/// `buildSidebarRows` filters and multi-key sorts every workspace, and the
/// sidebar used to run it inline on every rebuild while also mutating the
/// order memory during build.

@ProviderFor(workbenchSidebarRows)
final workbenchSidebarRowsProvider = WorkbenchSidebarRowsProvider._();

/// The sidebar row list, recomputed once per state change instead of once per
/// widget rebuild.
///
/// `buildSidebarRows` filters and multi-key sorts every workspace, and the
/// sidebar used to run it inline on every rebuild while also mutating the
/// order memory during build.

final class WorkbenchSidebarRowsProvider
    extends
        $FunctionalProvider<
          List<WorkbenchSidebarRow>,
          List<WorkbenchSidebarRow>,
          List<WorkbenchSidebarRow>
        >
    with $Provider<List<WorkbenchSidebarRow>> {
  /// The sidebar row list, recomputed once per state change instead of once per
  /// widget rebuild.
  ///
  /// `buildSidebarRows` filters and multi-key sorts every workspace, and the
  /// sidebar used to run it inline on every rebuild while also mutating the
  /// order memory during build.
  WorkbenchSidebarRowsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workbenchSidebarRowsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workbenchSidebarRowsHash();

  @$internal
  @override
  $ProviderElement<List<WorkbenchSidebarRow>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<WorkbenchSidebarRow> create(Ref ref) {
    return workbenchSidebarRows(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<WorkbenchSidebarRow> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<WorkbenchSidebarRow>>(value),
    );
  }
}

String _$workbenchSidebarRowsHash() =>
    r'f549c71cd45c77050faa6ce3d2908407e9911a01';

@ProviderFor(workspaceActivityRepository)
final workspaceActivityRepositoryProvider =
    WorkspaceActivityRepositoryProvider._();

final class WorkspaceActivityRepositoryProvider
    extends
        $FunctionalProvider<
          WorkspaceActivityRepository,
          WorkspaceActivityRepository,
          WorkspaceActivityRepository
        >
    with $Provider<WorkspaceActivityRepository> {
  WorkspaceActivityRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceActivityRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceActivityRepositoryHash();

  @$internal
  @override
  $ProviderElement<WorkspaceActivityRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceActivityRepository create(Ref ref) {
    return workspaceActivityRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceActivityRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceActivityRepository>(value),
    );
  }
}

String _$workspaceActivityRepositoryHash() =>
    r'e1bf0872d3ce08efa3e4848b1f5e9a995f928a9d';

/// Seeds [WorkspaceActivityController] from shared runtime state, merging the
/// legacy Drift timestamps during migration.

@ProviderFor(workspaceActivityPersistenceCoordinator)
final workspaceActivityPersistenceCoordinatorProvider =
    WorkspaceActivityPersistenceCoordinatorProvider._();

/// Seeds [WorkspaceActivityController] from shared runtime state, merging the
/// legacy Drift timestamps during migration.

final class WorkspaceActivityPersistenceCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Seeds [WorkspaceActivityController] from shared runtime state, merging the
  /// legacy Drift timestamps during migration.
  WorkspaceActivityPersistenceCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceActivityPersistenceCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspaceActivityPersistenceCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return workspaceActivityPersistenceCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$workspaceActivityPersistenceCoordinatorHash() =>
    r'7ae7aae0460472435ae00d4737f1f5ee19f4816c';

@ProviderFor(workspaceTabService)
final workspaceTabServiceProvider = WorkspaceTabServiceProvider._();

final class WorkspaceTabServiceProvider
    extends
        $FunctionalProvider<
          WorkspaceTabService,
          WorkspaceTabService,
          WorkspaceTabService
        >
    with $Provider<WorkspaceTabService> {
  WorkspaceTabServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceTabServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceTabServiceHash();

  @$internal
  @override
  $ProviderElement<WorkspaceTabService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceTabService create(Ref ref) {
    return workspaceTabService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceTabService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceTabService>(value),
    );
  }
}

String _$workspaceTabServiceHash() =>
    r'fb00e54f6d99f27461ff806e7a51443a68e10bb6';

@ProviderFor(workspaceFileService)
final workspaceFileServiceProvider = WorkspaceFileServiceProvider._();

final class WorkspaceFileServiceProvider
    extends
        $FunctionalProvider<
          WorkspaceFileService,
          WorkspaceFileService,
          WorkspaceFileService
        >
    with $Provider<WorkspaceFileService> {
  WorkspaceFileServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceFileServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceFileServiceHash();

  @$internal
  @override
  $ProviderElement<WorkspaceFileService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceFileService create(Ref ref) {
    return workspaceFileService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceFileService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceFileService>(value),
    );
  }
}

String _$workspaceFileServiceHash() =>
    r'caafbfd4f0d5e1241b84321d4ae06da175f89d9a';

@ProviderFor(workspaceSearchService)
final workspaceSearchServiceProvider = WorkspaceSearchServiceProvider._();

final class WorkspaceSearchServiceProvider
    extends
        $FunctionalProvider<
          WorkspaceSearchService,
          WorkspaceSearchService,
          WorkspaceSearchService
        >
    with $Provider<WorkspaceSearchService> {
  WorkspaceSearchServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceSearchServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceSearchServiceHash();

  @$internal
  @override
  $ProviderElement<WorkspaceSearchService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceSearchService create(Ref ref) {
    return workspaceSearchService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceSearchService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceSearchService>(value),
    );
  }
}

String _$workspaceSearchServiceHash() =>
    r'd4b42d3d093dad896f72742e1ba91f7a5e556d67';

@ProviderFor(managedWorkspaceRuntime)
final managedWorkspaceRuntimeProvider = ManagedWorkspaceRuntimeProvider._();

final class ManagedWorkspaceRuntimeProvider
    extends
        $FunctionalProvider<
          ManagedWorkspaceRuntime?,
          ManagedWorkspaceRuntime?,
          ManagedWorkspaceRuntime?
        >
    with $Provider<ManagedWorkspaceRuntime?> {
  ManagedWorkspaceRuntimeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'managedWorkspaceRuntimeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$managedWorkspaceRuntimeHash();

  @$internal
  @override
  $ProviderElement<ManagedWorkspaceRuntime?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ManagedWorkspaceRuntime? create(Ref ref) {
    return managedWorkspaceRuntime(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ManagedWorkspaceRuntime? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ManagedWorkspaceRuntime?>(value),
    );
  }
}

String _$managedWorkspaceRuntimeHash() =>
    r'4d245f24f6381f94006b0779a2b6e9fbc83328a6';

@ProviderFor(aleraCliTerminalShimService)
final aleraCliTerminalShimServiceProvider =
    AleraCliTerminalShimServiceProvider._();

final class AleraCliTerminalShimServiceProvider
    extends
        $FunctionalProvider<
          AleraCliTerminalShimService,
          AleraCliTerminalShimService,
          AleraCliTerminalShimService
        >
    with $Provider<AleraCliTerminalShimService> {
  AleraCliTerminalShimServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraCliTerminalShimServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraCliTerminalShimServiceHash();

  @$internal
  @override
  $ProviderElement<AleraCliTerminalShimService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AleraCliTerminalShimService create(Ref ref) {
    return aleraCliTerminalShimService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraCliTerminalShimService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraCliTerminalShimService>(value),
    );
  }
}

String _$aleraCliTerminalShimServiceHash() =>
    r'bb2421a929f9a17cda647871bd985645c8920ec8';

@ProviderFor(worktreeSetupRunner)
final worktreeSetupRunnerProvider = WorktreeSetupRunnerProvider._();

final class WorktreeSetupRunnerProvider
    extends
        $FunctionalProvider<
          WorktreeSetupRunner,
          WorktreeSetupRunner,
          WorktreeSetupRunner
        >
    with $Provider<WorktreeSetupRunner> {
  WorktreeSetupRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'worktreeSetupRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$worktreeSetupRunnerHash();

  @$internal
  @override
  $ProviderElement<WorktreeSetupRunner> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorktreeSetupRunner create(Ref ref) {
    return worktreeSetupRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorktreeSetupRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorktreeSetupRunner>(value),
    );
  }
}

String _$worktreeSetupRunnerHash() =>
    r'742cf23dff3e2a22adbe0a22b7dd37c0dcf66411';

@ProviderFor(editorSessionRegistry)
final editorSessionRegistryProvider = EditorSessionRegistryProvider._();

final class EditorSessionRegistryProvider
    extends
        $FunctionalProvider<
          EditorSessionRegistry,
          EditorSessionRegistry,
          EditorSessionRegistry
        >
    with $Provider<EditorSessionRegistry> {
  EditorSessionRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'editorSessionRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$editorSessionRegistryHash();

  @$internal
  @override
  $ProviderElement<EditorSessionRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  EditorSessionRegistry create(Ref ref) {
    return editorSessionRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EditorSessionRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EditorSessionRegistry>(value),
    );
  }
}

String _$editorSessionRegistryHash() =>
    r'3f997ee69df5530b86852aa45d68479905292df0';

@ProviderFor(workspaceService)
final workspaceServiceProvider = WorkspaceServiceProvider._();

final class WorkspaceServiceProvider
    extends
        $FunctionalProvider<
          WorkspaceService,
          WorkspaceService,
          WorkspaceService
        >
    with $Provider<WorkspaceService> {
  WorkspaceServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceServiceHash();

  @$internal
  @override
  $ProviderElement<WorkspaceService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WorkspaceService create(Ref ref) {
    return workspaceService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceService>(value),
    );
  }
}

String _$workspaceServiceHash() => r'dc769896af802de3483e877bfe9a1cbf232cfdf7';

@ProviderFor(terminalHostClient)
final terminalHostClientProvider = TerminalHostClientProvider._();

final class TerminalHostClientProvider
    extends
        $FunctionalProvider<
          TerminalHostClient,
          TerminalHostClient,
          TerminalHostClient
        >
    with $Provider<TerminalHostClient> {
  TerminalHostClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalHostClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalHostClientHash();

  @$internal
  @override
  $ProviderElement<TerminalHostClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TerminalHostClient create(Ref ref) {
    return terminalHostClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TerminalHostClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TerminalHostClient>(value),
    );
  }
}

String _$terminalHostClientHash() =>
    r'0c632a18c8f5ecdf6402c92ab03d6448bd861c80';

@ProviderFor(terminalHostWarmupCoordinator)
final terminalHostWarmupCoordinatorProvider =
    TerminalHostWarmupCoordinatorProvider._();

final class TerminalHostWarmupCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  TerminalHostWarmupCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalHostWarmupCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalHostWarmupCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return terminalHostWarmupCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$terminalHostWarmupCoordinatorHash() =>
    r'e22bebdd18897bb6b8284f1eb5cd5af21a2beda5';

@ProviderFor(terminalRuntime)
final terminalRuntimeProvider = TerminalRuntimeProvider._();

final class TerminalRuntimeProvider
    extends
        $FunctionalProvider<TerminalRuntime, TerminalRuntime, TerminalRuntime>
    with $Provider<TerminalRuntime> {
  TerminalRuntimeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalRuntimeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalRuntimeHash();

  @$internal
  @override
  $ProviderElement<TerminalRuntime> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TerminalRuntime create(Ref ref) {
    return terminalRuntime(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TerminalRuntime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TerminalRuntime>(value),
    );
  }
}

String _$terminalRuntimeHash() => r'93c7ddbf29f91e97f961f87bdad0460395e619aa';

@ProviderFor(terminalShellStartupPreparer)
final terminalShellStartupPreparerProvider =
    TerminalShellStartupPreparerProvider._();

final class TerminalShellStartupPreparerProvider
    extends
        $FunctionalProvider<
          TerminalShellStartupPreparer,
          TerminalShellStartupPreparer,
          TerminalShellStartupPreparer
        >
    with $Provider<TerminalShellStartupPreparer> {
  TerminalShellStartupPreparerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalShellStartupPreparerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalShellStartupPreparerHash();

  @$internal
  @override
  $ProviderElement<TerminalShellStartupPreparer> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TerminalShellStartupPreparer create(Ref ref) {
    return terminalShellStartupPreparer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TerminalShellStartupPreparer value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TerminalShellStartupPreparer>(value),
    );
  }
}

String _$terminalShellStartupPreparerHash() =>
    r'2ac712e1d4e187ae4fdef3b2789ec21f8f56e051';

@ProviderFor(terminalRuntimeExitCoordinator)
final terminalRuntimeExitCoordinatorProvider =
    TerminalRuntimeExitCoordinatorProvider._();

final class TerminalRuntimeExitCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  TerminalRuntimeExitCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalRuntimeExitCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalRuntimeExitCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return terminalRuntimeExitCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$terminalRuntimeExitCoordinatorHash() =>
    r'c06ba37819e3b0da9764d184a2ead782fb10e48e';

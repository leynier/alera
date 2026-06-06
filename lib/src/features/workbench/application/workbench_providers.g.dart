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
    r'a62f2a4b079041a3cef73c1d72aec8b378c2fdb3';

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
    r'b7726a6ea38683368a484b1c0015eebc3e65bda8';

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
    r'13bc331bb32ccb9ecb6c5f2f465edb8e34f935bb';

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

String _$workspaceServiceHash() => r'f9d3d65d61dcdf4f8edb8155472273e603fa04f0';

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
    r'ea5b5cddf9edea11464a47a5d5f469cc3fe17029';

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

String _$terminalRuntimeHash() => r'1f66acb9a085095d6e90bf5deb17842d335cac4e';

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
    r'c29c3c8c7baf565c55dc510a840f3996cff0160b';

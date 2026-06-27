// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspaceFolderOpener)
final workspaceFolderOpenerProvider = WorkspaceFolderOpenerProvider._();

final class WorkspaceFolderOpenerProvider
    extends
        $FunctionalProvider<
          WorkspaceFolderOpener,
          WorkspaceFolderOpener,
          WorkspaceFolderOpener
        >
    with $Provider<WorkspaceFolderOpener> {
  WorkspaceFolderOpenerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceFolderOpenerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceFolderOpenerHash();

  @$internal
  @override
  $ProviderElement<WorkspaceFolderOpener> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceFolderOpener create(Ref ref) {
    return workspaceFolderOpener(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceFolderOpener value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceFolderOpener>(value),
    );
  }
}

String _$workspaceFolderOpenerHash() =>
    r'9fab54d625cfe82b2b0bd97279fffbdb1a5bdc95';

@ProviderFor(projectService)
final projectServiceProvider = ProjectServiceProvider._();

final class ProjectServiceProvider
    extends $FunctionalProvider<ProjectService, ProjectService, ProjectService>
    with $Provider<ProjectService> {
  ProjectServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectServiceHash();

  @$internal
  @override
  $ProviderElement<ProjectService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProjectService create(Ref ref) {
    return projectService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectService>(value),
    );
  }
}

String _$projectServiceHash() => r'fe8756a547017f287e863db560a669b021bee8c0';

@ProviderFor(projectRepository)
final projectRepositoryProvider = ProjectRepositoryProvider._();

final class ProjectRepositoryProvider
    extends
        $FunctionalProvider<
          ProjectRepository,
          ProjectRepository,
          ProjectRepository
        >
    with $Provider<ProjectRepository> {
  ProjectRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectRepositoryHash();

  @$internal
  @override
  $ProviderElement<ProjectRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProjectRepository create(Ref ref) {
    return projectRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectRepository>(value),
    );
  }
}

String _$projectRepositoryHash() => r'e98deabcc5b6751754493b997b38927f13a3cd20';

@ProviderFor(projectList)
final projectListProvider = ProjectListProvider._();

final class ProjectListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Project>>,
          List<Project>,
          Stream<List<Project>>
        >
    with $FutureModifier<List<Project>>, $StreamProvider<List<Project>> {
  ProjectListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectListHash();

  @$internal
  @override
  $StreamProviderElement<List<Project>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Project>> create(Ref ref) {
    return projectList(ref);
  }
}

String _$projectListHash() => r'4d66818a67a56548b4074e2dc3461b7fee2d2149';

@ProviderFor(projectConfigRepository)
final projectConfigRepositoryProvider = ProjectConfigRepositoryProvider._();

final class ProjectConfigRepositoryProvider
    extends
        $FunctionalProvider<
          ProjectConfigRepository,
          ProjectConfigRepository,
          ProjectConfigRepository
        >
    with $Provider<ProjectConfigRepository> {
  ProjectConfigRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectConfigRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectConfigRepositoryHash();

  @$internal
  @override
  $ProviderElement<ProjectConfigRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProjectConfigRepository create(Ref ref) {
    return projectConfigRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectConfigRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectConfigRepository>(value),
    );
  }
}

String _$projectConfigRepositoryHash() =>
    r'8bb06d1831e52fe64496165f00724890d338267b';

@ProviderFor(projectConfigFileStore)
final projectConfigFileStoreProvider = ProjectConfigFileStoreProvider._();

final class ProjectConfigFileStoreProvider
    extends
        $FunctionalProvider<
          ProjectConfigFileStore,
          ProjectConfigFileStore,
          ProjectConfigFileStore
        >
    with $Provider<ProjectConfigFileStore> {
  ProjectConfigFileStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectConfigFileStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectConfigFileStoreHash();

  @$internal
  @override
  $ProviderElement<ProjectConfigFileStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProjectConfigFileStore create(Ref ref) {
    return projectConfigFileStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectConfigFileStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectConfigFileStore>(value),
    );
  }
}

String _$projectConfigFileStoreHash() =>
    r'85375f65b3a9e7d2705dd8c4eeddeddcdc700e65';

@ProviderFor(projectConfigService)
final projectConfigServiceProvider = ProjectConfigServiceProvider._();

final class ProjectConfigServiceProvider
    extends
        $FunctionalProvider<
          ProjectConfigService,
          ProjectConfigService,
          ProjectConfigService
        >
    with $Provider<ProjectConfigService> {
  ProjectConfigServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectConfigServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectConfigServiceHash();

  @$internal
  @override
  $ProviderElement<ProjectConfigService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProjectConfigService create(Ref ref) {
    return projectConfigService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectConfigService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectConfigService>(value),
    );
  }
}

String _$projectConfigServiceHash() =>
    r'43a0832c0320a6ae41d0f2d07cf13587f65681c9';

@ProviderFor(projectConfigOverrides)
final projectConfigOverridesProvider = ProjectConfigOverridesProvider._();

final class ProjectConfigOverridesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, ProjectConfig>>,
          Map<String, ProjectConfig>,
          Stream<Map<String, ProjectConfig>>
        >
    with
        $FutureModifier<Map<String, ProjectConfig>>,
        $StreamProvider<Map<String, ProjectConfig>> {
  ProjectConfigOverridesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectConfigOverridesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectConfigOverridesHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, ProjectConfig>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, ProjectConfig>> create(Ref ref) {
    return projectConfigOverrides(ref);
  }
}

String _$projectConfigOverridesHash() =>
    r'42e2465030fa288107b6eb7d069d5de204fc1bc6';

@ProviderFor(projectsService)
final projectsServiceProvider = ProjectsServiceProvider._();

final class ProjectsServiceProvider
    extends
        $FunctionalProvider<ProjectsService, ProjectsService, ProjectsService>
    with $Provider<ProjectsService> {
  ProjectsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectsServiceHash();

  @$internal
  @override
  $ProviderElement<ProjectsService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProjectsService create(Ref ref) {
    return projectsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectsService>(value),
    );
  }
}

String _$projectsServiceHash() => r'd92fe6a944980f570a0b9c0095dd7f6eed80ac58';

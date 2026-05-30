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

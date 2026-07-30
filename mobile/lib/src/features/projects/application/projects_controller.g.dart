// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'projects_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ProjectsController)
final projectsControllerProvider = ProjectsControllerFamily._();

final class ProjectsControllerProvider
    extends
        $AsyncNotifierProvider<ProjectsController, ProjectManagementSnapshot> {
  ProjectsControllerProvider._({
    required ProjectsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectsControllerHash();

  @override
  String toString() {
    return r'projectsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProjectsController create() => ProjectsController();

  @override
  bool operator ==(Object other) {
    return other is ProjectsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectsControllerHash() =>
    r'd44ea03574a4d8abf4438976062b4e3a92867781';

final class ProjectsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ProjectsController,
          AsyncValue<ProjectManagementSnapshot>,
          ProjectManagementSnapshot,
          FutureOr<ProjectManagementSnapshot>,
          String
        > {
  ProjectsControllerFamily._()
    : super(
        retry: null,
        name: r'projectsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ProjectsControllerProvider call(String hostId) =>
      ProjectsControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'projectsControllerProvider';
}

abstract class _$ProjectsController
    extends $AsyncNotifier<ProjectManagementSnapshot> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<ProjectManagementSnapshot> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<ProjectManagementSnapshot>,
              ProjectManagementSnapshot
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ProjectManagementSnapshot>,
                ProjectManagementSnapshot
              >,
              AsyncValue<ProjectManagementSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(HostDirectoryBrowserController)
final hostDirectoryBrowserControllerProvider =
    HostDirectoryBrowserControllerFamily._();

final class HostDirectoryBrowserControllerProvider
    extends
        $AsyncNotifierProvider<
          HostDirectoryBrowserController,
          HostDirectoryBrowserData
        > {
  HostDirectoryBrowserControllerProvider._({
    required HostDirectoryBrowserControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hostDirectoryBrowserControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hostDirectoryBrowserControllerHash();

  @override
  String toString() {
    return r'hostDirectoryBrowserControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  HostDirectoryBrowserController create() => HostDirectoryBrowserController();

  @override
  bool operator ==(Object other) {
    return other is HostDirectoryBrowserControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hostDirectoryBrowserControllerHash() =>
    r'743f31806bc1ce50242458b82529593e7e7b1910';

final class HostDirectoryBrowserControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          HostDirectoryBrowserController,
          AsyncValue<HostDirectoryBrowserData>,
          HostDirectoryBrowserData,
          FutureOr<HostDirectoryBrowserData>,
          String
        > {
  HostDirectoryBrowserControllerFamily._()
    : super(
        retry: null,
        name: r'hostDirectoryBrowserControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  HostDirectoryBrowserControllerProvider call(String hostId) =>
      HostDirectoryBrowserControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'hostDirectoryBrowserControllerProvider';
}

abstract class _$HostDirectoryBrowserController
    extends $AsyncNotifier<HostDirectoryBrowserData> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<HostDirectoryBrowserData> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<HostDirectoryBrowserData>,
              HostDirectoryBrowserData
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<HostDirectoryBrowserData>,
                HostDirectoryBrowserData
              >,
              AsyncValue<HostDirectoryBrowserData>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

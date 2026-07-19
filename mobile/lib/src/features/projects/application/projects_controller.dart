import 'dart:async';

import 'package:alera_mobile/src/features/projects/domain/project_management_models.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'projects_controller.g.dart';

class ProjectManagementSnapshot {
  const ProjectManagementSnapshot({
    required this.projects,
    required this.cloneJobs,
    required this.supported,
  });

  final List<ProjectSummary> projects;
  final List<ProjectCloneJob> cloneJobs;
  final bool supported;
}

@riverpod
class ProjectsController extends _$ProjectsController {
  StreamSubscription<Object?>? _eventsSubscription;

  @override
  Future<ProjectManagementSnapshot> build(String hostId) async {
    final client = await ref.watch(
      hostConnectionControllerProvider(hostId).future,
    );
    _eventsSubscription ??= client.events.listen((event) {
      if (event.name == 'projectsChanged' ||
          event.name == 'workspacesChanged' ||
          event.name == 'projectCloneJobsChanged' ||
          event.name == 'projectConfigsChanged') {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(() => unawaited(_eventsSubscription?.cancel()));
    final projects = await client.listProjects();
    final jobs = client.supportsProjectManagement
        ? await client.listProjectCloneJobs()
        : const <ProjectCloneJob>[];
    return ProjectManagementSnapshot(
      projects: projects,
      cloneJobs: jobs,
      supported: client.supportsProjectManagement,
    );
  }

  Future<ProjectRegistrationResult> registerProject({
    required String path,
    String? name,
  }) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    final result = await client.registerProject(path: path, name: name);
    ref.invalidateSelf();
    return result;
  }

  Future<ProjectSummary> renameProject(String id, String name) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    final project = await client.renameProject(id, name);
    ref.invalidateSelf();
    return project;
  }

  Future<ProjectRemovalPreview> previewRemoval(String id) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    return client.previewProjectRemoval(id);
  }

  Future<void> removeProject(String id) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    await client.removeProject(id);
    ref.invalidateSelf();
  }

  Future<ProjectCloneJob> startClone({
    required String url,
    required String parentPath,
    required String directoryName,
    String? name,
  }) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    final job = await client.startProjectClone(
      url: url,
      parentPath: parentPath,
      directoryName: directoryName,
      name: name,
    );
    ref.invalidateSelf();
    return job;
  }

  Future<void> cancelClone(String id) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    await client.cancelProjectClone(id);
    ref.invalidateSelf();
  }
}

class HostDirectoryBrowserData {
  const HostDirectoryBrowserData({required this.roots, this.listing});

  final List<HostDirectoryRoot> roots;
  final HostDirectoryListing? listing;
}

@riverpod
class HostDirectoryBrowserController extends _$HostDirectoryBrowserController {
  @override
  Future<HostDirectoryBrowserData> build(String hostId) async {
    final client = await ref.watch(
      hostConnectionControllerProvider(hostId).future,
    );
    return HostDirectoryBrowserData(roots: await client.hostDirectoryRoots());
  }

  Future<void> open(String path) async {
    final previous = state.value;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(
        hostConnectionControllerProvider(hostId).future,
      );
      return HostDirectoryBrowserData(
        roots: previous?.roots ?? await client.hostDirectoryRoots(),
        listing: await client.listHostDirectory(path),
      );
    });
  }

  void showRoots() {
    final current = state.value;
    if (current != null) {
      state = AsyncData(HostDirectoryBrowserData(roots: current.roots));
    }
  }
}

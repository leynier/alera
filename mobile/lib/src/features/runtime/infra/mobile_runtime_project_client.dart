import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/projects/domain/project_management_models.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_removal_dependency.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

mixin MobileRuntimeProjectClient {
  Set<String> get runtimeCapabilities;

  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]);

  bool get supportsProjectManagement =>
      runtimeCapabilities.contains(mobileProjectManagementCapability);

  Future<List<HostDirectoryRoot>> hostDirectoryRoots() async {
    final payload = await requestMap('hostDirectory.roots');
    return <HostDirectoryRoot>[
      for (final item
          in payload['roots'] as List<Object?>? ?? const <Object?>[])
        HostDirectoryRoot.fromJson(asJsonMap(item)),
    ];
  }

  Future<HostDirectoryListing> listHostDirectory(String path) async {
    return HostDirectoryListing.fromJson(
      await requestMap('hostDirectory.list', <String, Object?>{'path': path}),
    );
  }

  Future<ProjectRegistrationResult> registerProject({
    required String path,
    String? name,
  }) async {
    return ProjectRegistrationResult.fromJson(
      await requestMap('project.register', <String, Object?>{
        'path': path,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
  }

  Future<ProjectSummary> renameProject(String id, String name) async {
    return ProjectSummary.fromJson(
      await requestMap('project.rename', <String, Object?>{
        'id': id,
        'name': name,
      }),
    );
  }

  Future<ProjectRemovalPreview> previewProjectRemoval(String id) async {
    return ProjectRemovalPreview.fromJson(
      await requestMap('project.remove.preview', <String, Object?>{'id': id}),
    );
  }

  Future<List<WorkspaceRemovalDependency>> projectRemovalDependencies(
    String projectId,
  ) async {
    if (!runtimeCapabilities.contains(sharedCheckoutWorkspacesCapability)) {
      return const [];
    }
    final payload = await requestList(
      'project.removalDependencies',
      <String, Object?>{'id': projectId},
    );
    return payload
        .map((item) => WorkspaceRemovalDependency.fromJson(asJsonMap(item)))
        .toList(growable: false);
  }

  Future<void> pauseProjectRemovalDependencies(
    String projectId,
    List<WorkspaceRemovalDependency> approved,
  ) async {
    final approvedIds = approved.map((dependency) => dependency.id).toSet();
    for (final dependency in approved.where((item) => item.requiresPause)) {
      await request('automation.pause', <String, Object?>{
        'id': dependency.id,
        'activeRuns': 'cancel-active',
        'reason': 'Project removal requested',
      });
    }
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      final pending = (await projectRemovalDependencies(projectId))
          .where((dependency) => dependency.requiresPause)
          .toList();
      if (pending.isEmpty) return;
      if (pending.any((dependency) => !approvedIds.contains(dependency.id))) {
        throw StateError(
          'Automation dependencies changed. Refresh and confirm their impact again.',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Automation shutdown has not completed. The project was preserved; retry when its runs have stopped.',
        );
      }
      await Future.pause(const Duration(milliseconds: 250));
    }
  }

  Future<void> removeProject(String id) async {
    await request('project.remove', <String, Object?>{'id': id});
  }

  Future<ProjectCloneJob> startProjectClone({
    required String url,
    required String parentPath,
    required String directoryName,
    String? name,
  }) async {
    return ProjectCloneJob.fromJson(
      await requestMap('project.clone.start', <String, Object?>{
        'url': url,
        'parentPath': parentPath,
        'directoryName': directoryName,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
  }

  Future<List<ProjectCloneJob>> listProjectCloneJobs() async {
    final payload = await requestList('project.clone.list');
    return <ProjectCloneJob>[
      for (final item in payload) ProjectCloneJob.fromJson(asJsonMap(item)),
    ];
  }

  Future<void> cancelProjectClone(String id) async {
    await request('project.clone.cancel', <String, Object?>{'id': id});
  }

  Future<EffectiveMobileProjectConfig> effectiveProjectConfig(
    String projectId,
  ) async {
    return EffectiveMobileProjectConfig.fromJson(
      await requestMap('projectConfig.effective', <String, Object?>{
        'projectId': projectId,
      }),
    );
  }

  Future<void> saveProjectConfig(
    String projectId,
    MobileProjectConfig config,
  ) async {
    await request('projectConfig.upsert', <String, Object?>{
      'projectId': projectId,
      'config': config.toJson(),
    });
  }

  Future<void> useRepoProjectConfig(String projectId) async {
    await request('projectConfig.remove', <String, Object?>{
      'projectId': projectId,
    });
  }
}

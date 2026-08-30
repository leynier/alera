import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

mixin MobileRuntimeWorkspaceSidebarClient
    implements MobileWorkspaceSectionClient {
  @override
  bool get supportsWorkspaceSections =>
      runtimeCapabilities.contains('workspaceSectionsV1');
  @override
  Future<List<WorkspaceSectionSummary>> listWorkspaceSections() async => [
    for (final item in await requestList('workspaceSection.list'))
      WorkspaceSectionSummary.fromJson(asJsonMap(item)),
  ];
  @override
  Future<void> createWorkspaceSection(String name, String workspaceId) async {
    await request('workspaceSection.create', {
      'name': name,
      'workspaceId': workspaceId,
    });
  }

  @override
  Future<void> setWorkspaceSection(
    String workspaceId,
    String? sectionId,
  ) async {
    await request('workspaceSection.setForWorkspace', {
      'workspaceId': workspaceId,
      'sectionId': sectionId,
    });
  }

  @override
  Future<void> removeWorkspaceSection(String sectionId) async {
    await request('workspaceSection.remove', {'id': sectionId});
  }

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

  bool get supportsWorkspaceSidebarParity =>
      runtimeCapabilities.contains(mobileWorkspaceSidebarParityCapability);

  Future<WorkspaceSidebarSnapshot> workspaceSidebarSnapshot() async {
    return WorkspaceSidebarSnapshot.fromJson(
      await requestMap('workspaceSidebar.snapshot'),
    );
  }

  Future<MobileViewPrefs> loadWorkbenchViewPrefs() async {
    return _prefsForRuntime(await requestMap('workbenchViewPrefs.get'));
  }

  Future<MobileViewPrefs> updateWorkbenchViewPrefs(
    MobileViewPrefs prefs,
  ) async {
    final shared = prefs.toJson();
    if (!supportsWorkspaceSections) {
      shared.remove('sectionSort');
      shared.remove('collapsedSectionIds');
      shared.remove('othersSectionCollapsed');
      if (prefs.groupBy == MobileWorkspaceGroupBy.section) {
        shared['groupBy'] = 'project';
      }
    }
    return _prefsForRuntime(
      await requestMap('workbenchViewPrefs.update', <String, Object?>{
        'expectedRevision': prefs.revision,
        'prefs': shared,
      }),
    );
  }

  MobileViewPrefs _prefsForRuntime(Map<String, Object?> record) {
    final prefs = MobileViewPrefs.fromRecordJson(record);
    return !supportsWorkspaceSections &&
            prefs.groupBy == MobileWorkspaceGroupBy.section
        ? prefs.copyWith(groupBy: MobileWorkspaceGroupBy.project)
        : prefs;
  }

  Future<List<AgentPresenceSummary>> listAgentPresence() async {
    return <AgentPresenceSummary>[
      for (final item in await requestList('agentPresence.list'))
        AgentPresenceSummary.fromJson(asJsonMap(item)),
    ];
  }

  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String name,
  ) async {
    return WorkspaceSummary.fromJson(
      await requestMap('workspace.rename', <String, Object?>{
        'workspaceId': workspaceId,
        'name': name,
      }),
    );
  }

  Future<void> sleepWorkspace(String workspaceId) async {
    await request('workspace.sleep', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }

  Future<String?> workspaceRepositoryRemoteUrl(String workspaceId) async {
    final result = await requestMap(
      'workspace.repositoryWebUrl',
      <String, Object?>{'workspaceId': workspaceId},
    );
    return result.optionalString('remoteUrl');
  }

  Future<WorkspaceTagSummary> createWorkspaceTag(
    String name, {
    String? color,
  }) async {
    return WorkspaceTagSummary.fromJson(
      await requestMap('workspaceTag.create', <String, Object?>{
        'name': name,
        'color': ?color,
      }),
    );
  }

  Future<void> removeWorkspaceTag(String tagId) async {
    await request('workspaceTag.remove', <String, Object?>{'id': tagId});
  }

  Future<WorkspaceSummary> setWorkspaceTags(
    String workspaceId,
    List<String> tagIds,
  ) async {
    return WorkspaceSummary.fromJson(
      await requestMap('workspaceTag.setForWorkspace', <String, Object?>{
        'workspaceId': workspaceId,
        'tagIds': tagIds,
      }),
    );
  }
}

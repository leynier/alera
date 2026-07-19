import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

mixin MobileRuntimeWorkspaceSidebarClient {
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
    return MobileViewPrefs.fromRecordJson(
      await requestMap('workbenchViewPrefs.get'),
    );
  }

  Future<MobileViewPrefs> updateWorkbenchViewPrefs(
    MobileViewPrefs prefs,
  ) async {
    return MobileViewPrefs.fromRecordJson(
      await requestMap('workbenchViewPrefs.update', <String, Object?>{
        'expectedRevision': prefs.revision,
        'prefs': prefs.toJson(),
      }),
    );
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

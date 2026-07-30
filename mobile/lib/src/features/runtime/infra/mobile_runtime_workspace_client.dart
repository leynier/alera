import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

// Managed workspace lifecycle mirrors the desktop client timeouts
// (lib/src/features/workbench/infra/runtime_managed_workspace_client.dart).
const Duration _managedWorkspaceCreateTimeout = Duration(minutes: 30);
const Duration _managedWorkspaceRemoveTimeout = Duration(minutes: 10);

mixin MobileRuntimeWorkspaceClient {
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

  bool get supportsWorkspaceMutations =>
      runtimeCapabilities.contains(mobileWorkspaceMutationsCapability);

  bool get supportsPromptWorkspaceCreation =>
      runtimeCapabilities.contains(aiTextWorkspaceIdentityCapability) &&
      runtimeCapabilities.contains(agentProfilePromptLaunchCapability);

  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    await request('workspace.setPinned', <String, Object?>{
      'id': workspaceId,
      'isPinned': isPinned,
    });
  }

  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await request('workspaceRelation.link', <String, Object?>{
      'parentWorkspaceId': parentWorkspaceId,
      'childWorkspaceId': childWorkspaceId,
    });
  }

  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await request('workspaceRelation.unlink', <String, Object?>{
      'parentWorkspaceId': parentWorkspaceId,
      'childWorkspaceId': childWorkspaceId,
    });
  }

  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  }) async {
    final payload =
        await requestMap('workspace.createManaged', <String, Object?>{
          'projectId': projectId,
          'branch': branch,
          'reuseExistingBranch': reuseExistingBranch,
          if (!reuseExistingBranch && sourceBranch != null)
            'sourceBranch': sourceBranch,
          'name': ?name,
          'parentWorkspaceId': ?parentWorkspaceId,
        }, _managedWorkspaceCreateTimeout);
    return WorkspaceCreationResult.fromJson(payload);
  }

  Future<void> removeManagedWorkspace(
    String workspaceId, {
    bool? deleteBranch,
  }) async {
    await request('workspace.removeManaged', <String, Object?>{
      'id': workspaceId,
      'deleteBranch': ?deleteBranch,
    }, _managedWorkspaceRemoveTimeout);
  }

  Future<List<String>> cascadePreview(String workspaceId) async {
    final payload = await requestMap(
      'workspaceCascade.preview',
      <String, Object?>{
        'workspaceIds': <String>[workspaceId],
        'includeDescendants': true,
      },
    );
    return payload.stringList('workspaceIds');
  }

  Future<void> removeTab(String tabId) async {
    await request('tab.remove', <String, Object?>{'id': tabId});
  }

  Future<List<ProjectSummary>> listProjects() async {
    final payload = await requestList('project.list');
    return <ProjectSummary>[
      for (final item in payload)
        if (asJsonMap(item).isNotEmpty)
          ProjectSummary.fromJson(asJsonMap(item)),
    ];
  }

  Future<ProjectBranches> listBranches(String projectId) async {
    final payload = await requestMap('project.branches.list', <String, Object?>{
      'projectId': projectId,
    });
    return ProjectBranches.fromJson(payload);
  }

  Future<List<AgentProfileSummary>> listAgentProfiles() async {
    final payload = await requestMap('agentProfile.list');
    final items = payload['items'];
    if (items is! List) {
      return const <AgentProfileSummary>[];
    }
    return <AgentProfileSummary>[
      for (final item in items)
        if (item is Map)
          AgentProfileSummary.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Future<GeneratedWorkspaceIdentity> generateWorkspaceIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
  }) async {
    final payload = await requestMap(
      'aiText.workspaceIdentity.generate',
      <String, Object?>{
        'operationId': operationId,
        'projectId': projectId,
        'prompt': prompt,
      },
      const Duration(minutes: 11),
    );
    return GeneratedWorkspaceIdentity(
      workspaceName: payload.requiredString('workspaceName'),
      branchName: payload.requiredString('branchName'),
    );
  }

  Future<void> cancelWorkspaceIdentity(String operationId) async {
    await request('aiText.cancel', <String, Object?>{
      'operationId': operationId,
    });
  }

  Future<AgentProfileLaunchResult> launchAgentProfile({
    required String workspaceId,
    required String profileId,
    required String prompt,
  }) async {
    final payload = await requestMap('agentProfile.launch', <String, Object?>{
      'workspaceId': workspaceId,
      'profileId': profileId,
      'prompt': prompt,
    });
    final tab = payload.mapValue('tab');
    return AgentProfileLaunchResult(
      tabId: tab.requiredString('id'),
      agentType: payload.requiredString('agentType'),
    );
  }

  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final payload = await requestList('workspace.listAll');
    return <WorkspaceSummary>[
      for (final item in payload)
        if (asJsonMap(item).isNotEmpty)
          WorkspaceSummary.fromJson(asJsonMap(item)),
    ];
  }
}

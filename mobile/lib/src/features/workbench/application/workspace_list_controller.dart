import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_list_controller.g.dart';

const Set<String> _refreshEvents = <String>{
  'workspacesChanged',
  'workspaceRelationsChanged',
  'workspaceTabsChanged',
  'projectsChanged',
};

class WorkspaceListData {
  const WorkspaceListData({
    required this.workspaces,
    required this.projects,
    required this.supportsMutations,
  });

  final List<WorkspaceSummary> workspaces;
  final List<ProjectSummary> projects;

  /// False against runtimes that predate the mobile mutation allowlist; the
  /// UI hides mutating actions in that case.
  final bool supportsMutations;

  WorkspaceSummary? workspaceById(String id) {
    for (final workspace in workspaces) {
      if (workspace.id == id) {
        return workspace;
      }
    }
    return null;
  }
}

@riverpod
class WorkspaceListController extends _$WorkspaceListController {
  @override
  Future<WorkspaceListData> build(String hostId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    final subscription = client.events.listen((event) {
      if (_refreshEvents.contains(event.name)) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    final results = await Future.wait(<Future<Object?>>[
      client.listWorkspaces(),
      client.listProjects(),
    ]);
    return WorkspaceListData(
      workspaces: results[0]! as List<WorkspaceSummary>,
      projects: results[1]! as List<ProjectSummary>,
      supportsMutations: client.supportsWorkspaceMutations,
    );
  }

  Future<void> setPinned(String workspaceId, bool isPinned) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.setWorkspacePinned(workspaceId, isPinned);
    ref.invalidateSelf();
  }

  Future<void> linkParent({
    required String childWorkspaceId,
    required String parentWorkspaceId,
  }) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.linkWorkspaces(
      parentWorkspaceId: parentWorkspaceId,
      childWorkspaceId: childWorkspaceId,
    );
    ref.invalidateSelf();
  }

  Future<void> unlinkParent(WorkspaceSummary workspace) async {
    final parentId = workspace.parentWorkspaceId;
    if (parentId == null) {
      return;
    }
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.unlinkWorkspaces(
      parentWorkspaceId: parentId,
      childWorkspaceId: workspace.id,
    );
    ref.invalidateSelf();
  }

  Future<WorkspaceCreationResult> createWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
  }) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    final result = await client.createManagedWorkspace(
      projectId: projectId,
      branch: branch,
      sourceBranch: sourceBranch,
      reuseExistingBranch: reuseExistingBranch,
      name: name,
    );
    ref.invalidateSelf();
    return result;
  }

  Future<void> deleteWorkspace(String workspaceId, {bool? deleteBranch}) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.removeManagedWorkspace(
      workspaceId,
      deleteBranch: deleteBranch,
    );
    ref.invalidateSelf();
  }

  Future<List<String>> cascadePreview(String workspaceId) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    return client.cascadePreview(workspaceId);
  }
}

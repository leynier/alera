import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/deferred_workspace_setup_launcher.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_list_controller.g.dart';

const Set<String> _refreshEvents = <String>{
  'workspacesChanged',
  'workspaceRelationsChanged',
  'workspaceTabsChanged',
  'projectsChanged',
  'workspaceTagsChanged',
  'workspaceActivityChanged',
  'runtimeSettingsChanged',
  'agentPresenceChanged',
};

class const WorkspaceListData({
  required final List<WorkspaceSummary> workspaces,
  required final List<ProjectSummary> projects,
  required this.supportsMutations,
  final bool supportsPromptWorkspaceCreation = true,
  final bool supportsPromptImageUpload = false,
  final bool supportsPromptFileUpload = false,
  final bool supportsWorkspaceFiles = false,
  required final List<WorkspaceTagSummary> tags,
  required final Map<String, DateTime> activity,
  required final bool confirmWorkspaceRemoval,
  required final List<AgentPresenceSummary> agentPresence,
  final String? defaultAgentProfileId,
  final Map<String, int> terminalTabCountByWorkspaceId = const <String, int>{},
}) {
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
    if (!client.supportsWorkspaceSidebarParity) {
      throw UnsupportedError(
        'Update Alera on this host to use mobile workspaces.',
      );
    }
    if (ref.mounted) {
      final subscription = client.events.listen((event) {
        if (ref.mounted && _refreshEvents.contains(event.name)) {
          ref.invalidateSelf();
        }
      });
      ref.onDispose(subscription.cancel);
    }
    final snapshot = await client.workspaceSidebarSnapshot();
    return WorkspaceListData(
      workspaces: snapshot.workspaces,
      projects: snapshot.projects,
      supportsMutations: client.supportsWorkspaceMutations,
      supportsPromptWorkspaceCreation: client.supportsPromptWorkspaceCreation,
      supportsPromptImageUpload: client.supportsPromptImageUpload,
      // Sibling interface of MobileWorkspaceClient rather than a subtype: the
      // runtime client implements both, but neither promotes from the other.
      supportsPromptFileUpload:
          client is MobileCodexWorkspaceClient &&
          (client as MobileCodexWorkspaceClient).supportsPromptFileUpload,
      supportsWorkspaceFiles:
          client is MobileCodexWorkspaceClient &&
          (client as MobileCodexWorkspaceClient).supportsCodexWorkspaceFiles,
      tags: snapshot.tags,
      activity: snapshot.activity,
      confirmWorkspaceRemoval: snapshot.confirmWorkspaceRemoval,
      agentPresence: snapshot.agentPresence,
      defaultAgentProfileId: snapshot.defaultAgentProfileId,
      terminalTabCountByWorkspaceId: snapshot.terminalTabCountByWorkspaceId,
    );
  }

  Future<void> setPinned(String workspaceId, bool isPinned) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.setWorkspacePinned(workspaceId, isPinned);
    _invalidateIfMounted();
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
    _invalidateIfMounted();
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
    _invalidateIfMounted();
  }

  Future<WorkspaceCreationResult> createWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  }) async {
    final keepAlive = ref.keepAlive();
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      final creation = await client.createManagedWorkspace(
        projectId: projectId,
        branch: branch,
        sourceBranch: sourceBranch,
        reuseExistingBranch: reuseExistingBranch,
        name: name,
      );
      var result = creation;
      if (creation.hasDeferredSetup) {
        final terminalClient = await ref.read(
          terminalClientProvider(hostId).future,
        );
        result = await launchDeferredWorkspaceSetup(terminalClient, creation);
      }
      final parentId = parentWorkspaceId?.trim();
      if (parentId != null && parentId.isNotEmpty) {
        try {
          await client.linkWorkspaces(
            parentWorkspaceId: parentId,
            childWorkspaceId: creation.workspace.id,
          );
        } on Object catch (error) {
          result = result.withParentLinkError(error);
        }
      }
      _invalidateIfMounted();
      return result;
    } finally {
      keepAlive.close();
    }
  }

  Future<void> deleteWorkspace(String workspaceId, {bool? deleteBranch}) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.removeManagedWorkspace(
      workspaceId,
      deleteBranch: deleteBranch,
    );
    _invalidateIfMounted();
  }

  Future<List<String>> cascadePreview(String workspaceId) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    return client.cascadePreview(workspaceId);
  }

  Future<void> renameWorkspace(String workspaceId, String name) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.renameWorkspace(workspaceId, name);
    _invalidateIfMounted();
  }

  Future<void> sleepWorkspace(String workspaceId) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.sleepWorkspace(workspaceId);
    _invalidateIfMounted();
  }

  Future<String?> repositoryRemoteUrl(String workspaceId) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    return client.workspaceRepositoryRemoteUrl(workspaceId);
  }

  Future<WorkspaceTagSummary> createTag(String name, {String? color}) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    final tag = await client.createWorkspaceTag(name, color: color);
    _invalidateIfMounted();
    return tag;
  }

  Future<void> removeTag(String tagId) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.removeWorkspaceTag(tagId);
    _invalidateIfMounted();
  }

  Future<void> setTags(String workspaceId, List<String> tagIds) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.setWorkspaceTags(workspaceId, tagIds);
    _invalidateIfMounted();
  }

  void _invalidateIfMounted() {
    if (ref.mounted) {
      ref.invalidateSelf();
    }
  }
}

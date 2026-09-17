import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_removal_dependency.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

/// Workspace listing and mutation stubs shared by [FakeTerminalClient].
mixin FakeWorkspaceLifecycleClient {
  bool supportsSharedCheckoutWorkspaces = true;
  List<String> get calls;

  List<String> projectBranches = const <String>[];
  List<AgentProfileSummary> agentProfiles = const <AgentProfileSummary>[
    AgentProfileSummary(id: 'profile-1', name: 'Codex', agentType: 'codex'),
  ];
  GeneratedWorkspaceIdentity generatedWorkspaceIdentity =
      const GeneratedWorkspaceIdentity(
        workspaceName: 'Generated Workspace',
        branchName: 'feat/generated-workspace',
      );
  String? deferredSetupCommand;
  Object? linkError;
  int launchFailuresRemaining = 0;
  final List<String> agentLaunchMutationIds = <String>[];
  Future<void>? listAgentProfilesDelay;
  Future<void>? generateWorkspaceIdentityDelay;
  Object? listAgentProfilesError;
  bool? lastGenerateWorkspaceIdentityAutoAssign;

  List<ProjectSummary> projects = const <ProjectSummary>[];
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[];
  bool confirmWorkspaceRemoval = true;

  Future<WorkspaceSidebarSnapshot> workspaceSidebarSnapshot() async {
    return WorkspaceSidebarSnapshot(
      projects: projects,
      workspaces: workspaces,
      tags: const <WorkspaceTagSummary>[],
      activity: const <String, DateTime>{},
      viewPrefs: const MobileViewPrefs(),
      confirmWorkspaceRemoval: confirmWorkspaceRemoval,
    );
  }

  MobileViewPrefs viewPrefs = const MobileViewPrefs();

  Future<MobileViewPrefs> loadWorkbenchViewPrefs() async => viewPrefs;

  Future<MobileViewPrefs> updateWorkbenchViewPrefs(
    MobileViewPrefs prefs,
  ) async => viewPrefs = prefs.copyWith(revision: prefs.revision + 1);

  List<AgentPresenceSummary> agentPresence = const <AgentPresenceSummary>[];

  Future<List<AgentPresenceSummary>> listAgentPresence() async => agentPresence;

  Future<List<ProjectSummary>> listProjects() async {
    return projects;
  }

  Future<ProjectBranches> listBranches(
    String projectId, {
    String? checkoutHostId,
  }) async {
    return ProjectBranches(
      projectId: projectId,
      branches: projectBranches,
      localBranches: projectBranches,
    );
  }

  Future<List<AgentProfileSummary>> listAgentProfiles() async {
    final delay = listAgentProfilesDelay;
    if (delay != null) {
      await delay;
    }
    final error = listAgentProfilesError;
    if (error != null) {
      throw error;
    }
    return agentProfiles;
  }

  Future<GeneratedWorkspaceIdentity> generateWorkspaceIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
    bool autoAssignSection = false,
  }) async {
    calls.add('generateWorkspaceIdentity $projectId');
    lastGenerateWorkspaceIdentityAutoAssign = autoAssignSection;
    final delay = generateWorkspaceIdentityDelay;
    if (delay != null) {
      await delay;
    }
    return generatedWorkspaceIdentity;
  }

  Future<void> cancelWorkspaceIdentity(String operationId) async {
    calls.add('cancelWorkspaceIdentity $operationId');
  }

  Future<AgentProfileLaunchResult> launchAgentProfile({
    required String workspaceId,
    required String profileId,
    String prompt = '',
    required String clientMutationId,
  }) async {
    agentLaunchMutationIds.add(clientMutationId);
    calls.add('launchAgentProfile $workspaceId $profileId $prompt');
    if (launchFailuresRemaining > 0) {
      launchFailuresRemaining -= 1;
      throw StateError('launch response was lost');
    }
    return const AgentProfileLaunchResult(
      tabId: 'agent-tab',
      agentType: 'codex',
    );
  }

  Future<List<WorkspaceSummary>> listWorkspaces() async {
    return workspaces;
  }

  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    calls.add('setPinned $workspaceId $isPinned');
  }

  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('link $parentWorkspaceId $childWorkspaceId');
    final error = linkError;
    if (error != null) {
      throw error;
    }
  }

  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('unlink $parentWorkspaceId $childWorkspaceId');
  }

  Future<List<WorkspaceRemovalDependency>> removalDependencies(
    String workspaceId,
  ) async => const [];
  Future<void> pauseRemovalDependencies(
    String workspaceId,
    List<WorkspaceRemovalDependency> approved,
  ) async {}

  Future<WorkspaceCreationResult> createSharedWorkspace({
    required String projectId,
    String? name,
    String? checkoutHostId,
    String? issueUrl,
  }) async {
    calls.add('createSharedWorkspace $projectId');
    return WorkspaceCreationResult(
      workspace: WorkspaceSummary(
        id: 'created',
        projectId: projectId,
        name: name ?? 'Workspace 1',
        path: '/tmp/project',
        kind: 'main',
      ),
      steps: const <WorkspaceSetupStep>[],
    );
  }

  Future<void> removeSharedWorkspace(String workspaceId) async {
    calls.add('removeSharedWorkspace $workspaceId');
  }

  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    String? checkoutHostId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
    String? issueUrl,
  }) async {
    calls.add('createWorkspace $projectId $branch');
    return WorkspaceCreationResult(
      workspace: WorkspaceSummary(
        id: 'created',
        projectId: projectId,
        name: name ?? branch,
        path: '/tmp/created',
      ),
      steps: const <WorkspaceSetupStep>[],
      deferredSetupCommand: deferredSetupCommand,
    );
  }

  Future<void> removeManagedWorkspace(
    String workspaceId, {
    bool? deleteBranch,
  }) async {
    calls.add('removeWorkspace $workspaceId $deleteBranch');
  }

  Future<List<String>> cascadePreview(String workspaceId) async {
    return <String>[workspaceId];
  }

  Future<WorkspaceSummary> renameWorkspace(String id, String name) async =>
      WorkspaceSummary(id: id, projectId: 'p1', name: name, path: '/tmp/$id');

  Future<void> sleepWorkspace(String workspaceId) async {}

  Future<String?> workspaceRepositoryRemoteUrl(String workspaceId) async =>
      null;

  Future<WorkspaceTagSummary> createWorkspaceTag(
    String name, {
    String? color,
  }) async => WorkspaceTagSummary(id: name, name: name, color: color);

  Future<void> removeWorkspaceTag(String tagId) async {}

  Future<WorkspaceSummary> setWorkspaceTags(
    String workspaceId,
    List<String> tagIds,
  ) async => WorkspaceSummary(
    id: workspaceId,
    projectId: 'p1',
    name: workspaceId,
    path: '/tmp/$workspaceId',
    tagIds: tagIds,
  );
}

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';

// A two-project workbench with a linked attempt worktree, shared by the
// automation and recipe suites.
WorkbenchState boardWorkbenchState() {
  final now = DateTime.utc(2026, 8, 30);
  final projects = [
    for (final id in ['1', '2'])
      Project(
        id: 'project-$id',
        name: id == '1' ? 'Alera' : 'Other Project',
        repoPath: '/project/$id',
        createdAt: now,
        updatedAt: now,
      ),
  ];
  final workspaces = [
    for (final id in ['1', '2'])
      Workspace(
        id: 'ws-$id',
        projectId: 'project-$id',
        name: id == '1' ? 'Workflow Delivery' : 'Current Workspace',
        path: '/project/$id',
        branch: 'main',
        createdAt: now,
        updatedAt: now,
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      ),
    Workspace(
      id: 'workflow-attempt-2',
      projectId: 'project-1',
      name: 'Workflow Attempt 2',
      path: '/projects/alera/workflow-attempt-2',
      branch: 'alera/workflows/workflow-attempt-2',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
    ),
  ];
  return WorkbenchState(
    projects: projects,
    workspacesByProject: {
      for (final project in projects)
        project.id: workspaces
            .where((workspace) => workspace.projectId == project.id)
            .toList(),
    },
    tabsByWorkspace: {
      'ws-1': [
        WorkspaceTabRecord(
          id: 'main-session-1',
          workspaceId: 'ws-1',
          title: 'Main Terminal',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      'workflow-attempt-2': [
        WorkspaceTabRecord(
          id: 'session-1',
          workspaceId: 'workflow-attempt-2',
          title: 'Implementation',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    },
    activeProjectId: 'project-2',
    activeWorkspaceId: 'ws-2',
    bootstrapped: true,
  );
}

class BoardTestWorkbench extends WorkbenchController {
  BoardTestWorkbench({this.seed});
  final WorkbenchState? seed;
  final actions = <String>[];
  @override
  WorkbenchState build() => seed ?? boardWorkbenchState();
  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    actions.add('workspace:${workspace.id}');
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
    );
  }

  @override
  Future<void> selectWorkspaceTab({
    required String workspaceId,
    required String tabId,
  }) async {
    actions.add('terminal:$tabId');
  }

  @override
  Future<WorkspaceTabRecord> openGitDiffTab({
    required Workspace workspace,
    String? relativePath,
    GitChangeArea? area,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
    bool oppositePanel = false,
  }) async {
    actions.add('diff:${workspace.id}');
    final now = DateTime.utc(2026);
    return WorkspaceTabRecord(
      id: 'diff',
      workspaceId: workspace.id,
      title: 'Diff',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceTabKind.gitDiff,
    );
  }

  @override
  Future<WorkspaceTabRecord> openGitCommitDiffTab({
    required Workspace workspace,
    String? relativePath,
    String? oldPath,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    required String commitOid,
    String? parentOid,
    required String compareRef,
    String? subject,
    String? message,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
    bool oppositePanel = false,
  }) async {
    actions.add('commitDiff:${workspace.id}:$parentOid:$commitOid');
    final now = DateTime.utc(2026);
    return WorkspaceTabRecord(
      id: 'commit-diff',
      workspaceId: workspace.id,
      title: 'Workflow Result',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceTabKind.gitDiff,
    );
  }
}

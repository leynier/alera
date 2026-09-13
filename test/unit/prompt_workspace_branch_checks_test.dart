import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_branch_catalog.dart';
import 'package:alera/src/features/workbench/application/prompt_workspace_branch_checks.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';

void main() {
  test('background SSH branch checks ignore local branches and unavailable local paths', () async {
    final now = DateTime.utc(2026);
    final project = Project(
      id: 'project',
      name: 'Project',
      repoPath: '/missing/local',
      createdAt: now,
      updatedAt: now,
    );
    final git = FakeGitBackend()..sourceBranches = ['only-local'];
    Workspace task(String id, String host, String branch) => Workspace(
      id: id,
      projectId: project.id,
      name: id,
      path: '/repo',
      hostId: host,
      branch: branch,
      kind: .linked,
      status: .active,
      createdAt: now,
      updatedAt: now,
    );
    final checks = PromptWorkspaceBranchChecks(
      hostId: 'ssh',
      git: git,
      workspaces: () => [
        task('local', 'local', 'local-task'),
        task('remote', 'ssh', 'remote-task'),
        task('other', 'another-ssh', 'foreign-task'),
      ],
      loadHostCatalog: (requested, host) async {
        expect(requested.id, project.id);
        expect(host, 'ssh');
        return ProjectBranchCatalog(
          projectId: project.id,
          hostId: 'ssh',
          branches: ['only-remote'],
          localBranches: {'only-remote'},
        );
      },
    );
    expect(await checks.branchExists(project, 'only-local'), isFalse);
    expect(await checks.branchExists(project, 'only-remote'), isTrue);
    expect(checks.workspaceBranches(project), {'remote-task'});
    expect(git.calls, isEmpty);
  });
}

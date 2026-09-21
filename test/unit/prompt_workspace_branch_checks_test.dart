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

  test('a remote-only project without a host asks its own host', () async {
    final now = DateTime.utc(2026);
    final local = Project(
      id: 'local',
      name: 'Local',
      repoPath: '/repo/local',
      createdAt: now,
      updatedAt: now,
    );
    final remoteOnly = local.copyWith(
      id: 'remote',
      repoPath: '/srv/only-there',
      primaryHostId: 'ssh',
    );
    final git = FakeGitBackend()..sourceBranches = ['only-local'];
    final hosts = <String?>[];
    final checks = PromptWorkspaceBranchChecks(
      hostId: null,
      git: git,
      workspaces: () => const <Workspace>[],
      loadHostCatalog: (requested, host) async {
        hosts.add(host);
        return ProjectBranchCatalog(
          projectId: requested.id,
          hostId: host ?? 'local',
          branches: const ['only-remote'],
          localBranches: const {'only-remote'},
        );
      },
    );

    expect(await checks.branchExists(remoteOnly, 'only-remote'), isTrue);
    expect(await checks.branchExists(remoteOnly, 'only-local'), isFalse);
    expect(hosts, <String?>['ssh', 'ssh']);
    expect(git.calls, isEmpty);

    expect(await checks.branchExists(local, 'only-local'), isTrue);
    expect(git.calls.single.method, 'branchExists');
  });
}

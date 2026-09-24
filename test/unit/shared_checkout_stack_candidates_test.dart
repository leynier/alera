import 'package:alera/src/features/pull_requests/presentation/workspace_pull_request_stack_candidates.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared tasks contribute a branch once and retain the current task', () {
    final candidates = buildReviewStackWorkspaceCandidates(
      workspaces: [
        _workspace('first'),
        _workspace('current'),
        _workspace('linked', branch: 'topic', path: '/worktree', kind: .linked),
      ],
      currentWorkspaceId: 'current',
      currentRepoPath: '/repo',
    );
    final deduplicated = applyLiveReviewStackWorkspaceBranch(
      candidates: candidates,
      branch: null,
    );
    expect(deduplicated.map((candidate) => candidate.workspaceId), [
      'current',
      'linked',
    ]);
  });

  test('live branch correction preserves a different worktree with the cached branch', () {
    final candidates = buildReviewStackWorkspaceCandidates(
      workspaces: [
        _workspace('current', branch: 'old'),
        _workspace('other', branch: 'old', path: '/other', kind: .linked),
      ],
      currentWorkspaceId: 'current',
      currentRepoPath: '/repo',
    );
    final corrected = applyLiveReviewStackWorkspaceBranch(
      candidates: candidates,
      branch: 'new',
    );
    expect(corrected.map((candidate) => candidate.branch), ['new', 'old']);
  });

  test('equal branch names on separate hosts are not conflated', () {
    final candidates = buildReviewStackWorkspaceCandidates(
      workspaces: [
        _workspace('local'),
        _workspace('remote', hostId: 'ssh'),
      ],
      currentWorkspaceId: 'local',
      currentRepoPath: '/repo',
    );
    expect(candidates, hasLength(2));
    final live = applyLiveReviewStackWorkspaceBranch(
      candidates: candidates,
      branch: 'local-change',
    );
    expect(
      live.firstWhere((candidate) => candidate.workspaceId == 'remote').branch,
      'main',
    );
  });

  test('live branch changes do not retain stale duplicate stack layers', () {
    final candidates = buildReviewStackWorkspaceCandidates(
      workspaces: [
        _workspace('current'),
        _workspace('stale', branch: 'old'),
      ],
      currentWorkspaceId: 'current',
      currentRepoPath: '/repo',
    );
    final live = applyLiveReviewStackWorkspaceBranch(
      candidates: candidates,
      branch: 'new',
    );
    expect(live, hasLength(1));
    expect(live.single.workspaceId, 'current');
    expect(live.single.branch, 'new');
  });
}

Workspace _workspace(
  String id, {
  String hostId = 'local',
  String branch = 'main',
  String path = '/repo',
  WorkspaceKind kind = .main,
}) => Workspace(
  id: id,
  projectId: 'project',
  name: id,
  hostId: hostId,
  branch: branch,
  path: path,
  kind: kind,
  status: .active,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WorkspaceGitQuickActionState resolve({
    bool changes = false,
    bool remote = true,
    bool pr = false,
    bool canCreate = true,
    bool defaultBranch = false,
    bool delta = false,
    bool busy = false,
    int ahead = 0,
    int behind = 0,
    bool conflicts = false,
    String branch = 'feature',
    String? headMessage,
  }) => resolveWorkspaceGitQuickAction(
    repository: GitRepositoryState(
      branch: branch,
      ahead: ahead,
      behind: behind,
      hasConflicts: conflicts,
      headMessage: headMessage,
    ),
    hasChanges: changes,
    hasRemote: remote,
    hasOpenPr: pr,
    canCreatePr: canCreate,
    isDefaultBranch: defaultBranch,
    hasBranchChanges: delta,
    busy: busy,
  );
  test('selects a commit action using remote, branch and PR state', () {
    expect(
      resolve(changes: true, remote: false).action,
      WorkspaceGitQuickAction.commit,
    );
    expect(resolve(changes: true).action, WorkspaceGitQuickAction.commitPushPr);
    expect(
      resolve(changes: true, defaultBranch: true).action,
      WorkspaceGitQuickAction.commitPush,
    );
    expect(
      resolve(changes: true, pr: true).action,
      WorkspaceGitQuickAction.commitPush,
    );
    expect(
      resolve(changes: true, canCreate: false).action,
      WorkspaceGitQuickAction.commitPush,
    );
  });
  test('pulls behind branches and pushes outgoing work', () {
    expect(resolve(behind: 1).action, WorkspaceGitQuickAction.pull);
    expect(resolve(ahead: 1).action, WorkspaceGitQuickAction.createPr);
    expect(
      resolve(ahead: 1, defaultBranch: true).action,
      WorkspaceGitQuickAction.push,
    );
    expect(resolve(ahead: 1, pr: true).action, WorkspaceGitQuickAction.push);
    expect(
      resolve(ahead: 1, canCreate: false).action,
      WorkspaceGitQuickAction.push,
    );
    expect(resolve(delta: true).action, WorkspaceGitQuickAction.createPr);
  });
  test('blocks incompatible states and clean checkouts', () {
    for (final result in [
      resolve(),
      resolve(busy: true),
      resolve(conflicts: true),
      resolve(branch: 'HEAD'),
      resolve(ahead: 1, behind: 1),
      resolve(delta: true, remote: false),
    ]) {
      expect(result.action, isNull);
      expect(result.hint, isNotEmpty);
      expect(result.label, 'Commit');
    }
  });
  test('unpublished commits can push without a forge or upstream', () {
    expect(
      resolve(headMessage: 'feat: branch work', canCreate: false).action,
      WorkspaceGitQuickAction.push,
    );
    expect(
      resolve(headMessage: 'feat: branch work', defaultBranch: true).action,
      WorkspaceGitQuickAction.push,
    );
  });
  test(
    'behind or diverged branches can commit locally while push is blocked',
    () {
      expect(
        resolve(changes: true, behind: 1).action,
        WorkspaceGitQuickAction.commit,
      );
      expect(
        resolve(changes: true, ahead: 1, behind: 1).action,
        WorkspaceGitQuickAction.commit,
      );
    },
  );
  test('declares the steps each action includes', () {
    for (final action in WorkspaceGitQuickAction.values) {
      expect(action.label, isNotEmpty);
      expect(
        action.includesCommit,
        [
          WorkspaceGitQuickAction.commit,
          WorkspaceGitQuickAction.commitPush,
          WorkspaceGitQuickAction.commitPushPr,
        ].contains(action),
      );
      expect(
        action.includesPr,
        [
          WorkspaceGitQuickAction.commitPushPr,
          WorkspaceGitQuickAction.createPr,
        ].contains(action),
      );
      expect(WorkspaceGitQuickActionState(action: action).label, action.label);
    }
  });
}

import 'package:alera/src/features/workbench/application/workspace_handoff_context.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';

void main() {
  test(
    'context includes tracked staged and unstaged diffs, untracked names only',
    () async {
      final git = FakeGitBackend()
        ..gitStatusResult = const GitStatusResult(
          entries: [
            GitChangeEntry(
              path: 'src/main.dart',
              area: .staged,
              status: .modified,
            ),
            GitChangeEntry(
              path: 'src/main.dart',
              area: .unstaged,
              status: .modified,
            ),
            GitChangeEntry(
              path: 'scratch.txt',
              area: .untracked,
              status: .untracked,
            ),
            GitChangeEntry(
              path: '.env.local',
              area: .staged,
              status: .modified,
            ),
            GitChangeEntry(
              path: 'private.key',
              area: .unstaged,
              status: .modified,
            ),
          ],
        );
      final context = await workspaceHandoffContext(
        git: git,
        path: '/repo',
        workspaceName: 'Feature',
        agentTitles: ['Fix Login'],
        projectName: 'Project',
        agentContext: ['Profile: Codex', 'Task: Repair login'],
      );
      final diffs = git.calls.where((call) => call.method == 'diff').toList();
      expect(diffs.length, 2);
      expect(context, contains('scratch.txt'));
      expect(context, contains('Fix Login'));
      expect(context, contains('Profile: Codex'));
      expect(context, contains('Task: Repair login'));
    },
  );

  test('context remains bounded for large metadata and diff lines', () async {
    final git = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: [
          GitChangeEntry(path: 'source', area: .staged, status: .modified),
        ],
      )
      ..gitDiffResult = GitDiffResult(
        files: [
          GitDiffFile(
            path: 'source',
            area: .staged,
            status: .modified,
            lines: [GitDiffLine.addition('x' * 100000)],
          ),
        ],
      );
    final context = await workspaceHandoffContext(
      git: git,
      path: '/repo',
      workspaceName: 'w' * 100000,
      agentTitles: ['a' * 100000],
      agentContext: ['p' * 100000],
    );
    expect(context.length, lessThanOrEqualTo(12000));
    expect(context, contains('staged: source'));
  });
}

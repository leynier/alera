import 'dart:io';

import 'package:alera/src/features/worktree/application/worktree_service.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fakes.dart';

void main() {
  group('WorktreeService', () {
    test('creates worktree with provided base branch', () async {
      final repoDir = Directory.systemTemp.createTempSync('alera-worktree-');
      final processRunner = FakeProcessRunner();
      processRunner.queuedResults.add(
        const ProcessRunOutput(exitCode: 0, stdout: '', stderr: ''),
      );

      final service = WorktreeService(
        processRunner: processRunner,
        branchNameGenerator: FakeBranchNameGenerator('alera/my-branch'),
      );

      final spec = await service.createWorktree(
        repoPath: repoDir.path,
        firstPrompt: 'my prompt',
        baseBranch: 'main',
        autoPull: false,
        now: DateTime.utc(2026, 2, 20),
      );

      expect(spec.branchName, 'alera/my-branch');
      expect(spec.baseBranch, 'main');
      expect(processRunner.calls, hasLength(1));
      expect(processRunner.calls.first.arguments.take(4),
          <String>['worktree', 'add', '-b', 'alera/my-branch']);
      repoDir.deleteSync(recursive: true);
    });

    test('pulls base branch first when autoPull is enabled', () async {
      final repoDir = Directory.systemTemp.createTempSync('alera-worktree-');
      final processRunner = FakeProcessRunner();
      processRunner.queuedResults.addAll(<ProcessRunOutput>[
        const ProcessRunOutput(exitCode: 0, stdout: '', stderr: ''),
        const ProcessRunOutput(exitCode: 0, stdout: '', stderr: ''),
      ]);

      final service = WorktreeService(
        processRunner: processRunner,
        branchNameGenerator: FakeBranchNameGenerator('alera/my-branch'),
      );

      await service.createWorktree(
        repoPath: repoDir.path,
        firstPrompt: 'my prompt',
        baseBranch: 'main',
        autoPull: true,
      );

      expect(processRunner.calls, hasLength(2));
      expect(
        processRunner.calls.first.arguments,
        <String>['pull', 'origin', 'main'],
      );
      expect(processRunner.calls.last.arguments.first, 'worktree');
      repoDir.deleteSync(recursive: true);
    });

    test('removes worktree using git command', () async {
      final processRunner = FakeProcessRunner();
      processRunner.queuedResults.add(
        const ProcessRunOutput(exitCode: 0, stdout: '', stderr: ''),
      );

      final service = WorktreeService(
        processRunner: processRunner,
        branchNameGenerator: FakeBranchNameGenerator('alera/my-branch'),
      );

      await service.removeWorktree(
        repoPath: '/repo',
        worktreePath: '/repo/.alera/worktrees/alera-my-branch',
        force: true,
      );

      expect(
        processRunner.calls.single.arguments,
        <String>[
          'worktree',
          'remove',
          '--force',
          '/repo/.alera/worktrees/alera-my-branch',
        ],
      );
    });
  });
}

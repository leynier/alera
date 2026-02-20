import 'dart:io';

import 'package:alera/src/features/worktree/application/branch_name_generator.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:path/path.dart' as p;

class WorktreeService {
  WorktreeService({
    required ProcessRunner processRunner,
    required BranchNameResolver branchNameGenerator,
  })  : _processRunner = processRunner,
        _branchNameGenerator = branchNameGenerator;

  final ProcessRunner _processRunner;
  final BranchNameResolver _branchNameGenerator;

  Future<WorktreeSpec> createWorktree({
    required String repoPath,
    required String firstPrompt,
    String? baseBranch,
    required bool autoPull,
    DateTime? now,
  }) async {
    final resolvedBaseBranch =
        baseBranch ?? await _detectDefaultBranch(repoPath) ?? 'main';

    if (autoPull) {
      final pullResult = await _processRunner.run(
        'git',
        <String>['pull', 'origin', resolvedBaseBranch],
        workingDirectory: repoPath,
      );
      if (pullResult.exitCode != 0) {
        throw StateError('failed to pull base branch: ${pullResult.stderr}');
      }
    }

    final branchName = await _branchNameGenerator.generate(
      firstPrompt: firstPrompt,
      now: now ?? DateTime.now().toUtc(),
    );

    final worktreePath = p.join(
      repoPath,
      '.alera',
      'worktrees',
      branchName.replaceAll('/', '-'),
    );

    Directory(worktreePath).createSync(recursive: true);

    final addResult = await _processRunner.run(
      'git',
      <String>['worktree', 'add', '-b', branchName, worktreePath, resolvedBaseBranch],
      workingDirectory: repoPath,
    );

    if (addResult.exitCode != 0) {
      throw StateError('failed to create worktree: ${addResult.stderr}');
    }

    return WorktreeSpec(
      branchName: branchName,
      worktreePath: worktreePath,
      baseBranch: resolvedBaseBranch,
    );
  }

  Future<void> removeWorktree({
    required String repoPath,
    required String worktreePath,
    bool force = false,
  }) async {
    final args = <String>['worktree', 'remove'];
    if (force) {
      args.add('--force');
    }
    args.add(worktreePath);

    final result = await _processRunner.run(
      'git',
      args,
      workingDirectory: repoPath,
    );

    if (result.exitCode != 0) {
      throw StateError('failed to remove worktree: ${result.stderr}');
    }
  }

  Future<String?> _detectDefaultBranch(String repoPath) async {
    final result = await _processRunner.run(
      'git',
      <String>['symbolic-ref', 'refs/remotes/origin/HEAD'],
      workingDirectory: repoPath,
    );

    if (result.exitCode != 0) {
      return null;
    }

    final stdout = result.stdout.trim();
    if (stdout.isEmpty || !stdout.contains('/')) {
      return null;
    }

    return stdout.split('/').last;
  }
}

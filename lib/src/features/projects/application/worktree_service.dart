import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class WorktreeException implements Exception {
  WorktreeException(this.message, {this.stderr});

  final String message;
  final String? stderr;

  @override
  String toString() {
    if (stderr == null || stderr!.trim().isEmpty) {
      return message;
    }
    return '$message: ${stderr!.trim()}';
  }
}

/// Resolves the on-disk root for Alera-managed worktrees. Defaults to
/// `~/.alera/worktrees`. Set [override] in tests.
class WorktreeRoot {
  WorktreeRoot({this._override});

  final String? _override;

  String resolve() {
    if (_override != null) {
      return _override;
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw WorktreeException('Cannot locate user home directory');
    }
    return p.join(home, '.alera', 'worktrees');
  }
}

class WorktreeService {
  WorktreeService({
    required this._projectRepository,
    required this._processRunner,
    WorktreeRoot? worktreeRoot,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _worktreeRoot = worktreeRoot ?? WorktreeRoot(),
       _uuid = uuid ?? const Uuid(),
       _now = now ?? _defaultNow;

  final ProjectRepository _projectRepository;
  final ProcessRunner _processRunner;
  final WorktreeRoot _worktreeRoot;
  final Uuid _uuid;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  /// Validates a raw worktree name and returns its slug. Throws
  /// [WorktreeException] when the input cannot be normalized into the allowed
  /// `[a-z0-9-]+` pattern.
  String slugify(String input) {
    final trimmed = input.trim().toLowerCase();
    final replaced = trimmed
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (replaced.isEmpty) {
      throw WorktreeException(
        'Worktree name must contain at least one [a-z0-9-] character',
      );
    }
    return replaced;
  }

  String resolveWorktreePath(Project project, String slug) {
    final repoSlug = _repoSlug(project);
    return p.join(_worktreeRoot.resolve(), repoSlug, slug);
  }

  String resolveBranch(String slug) => 'alera/$slug';

  Future<Worktree> create({
    required Project project,
    required String name,
  }) async {
    final slug = slugify(name);
    final existing = await _projectRepository.listWorktrees(project.id);
    if (existing.any(
      (w) => w.name == slug && w.status == WorktreeStatus.active,
    )) {
      throw WorktreeException(
        'Worktree with name "$slug" already exists for this project',
      );
    }
    final branch = resolveBranch(slug);
    final path = resolveWorktreePath(project, slug);
    final parent = Directory(p.dirname(path));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    final result = await _processRunner.run('git', <String>[
      'worktree',
      'add',
      '-b',
      branch,
      path,
    ], workingDirectory: project.repoPath);
    if (result.exitCode != 0) {
      throw WorktreeException(
        'git worktree add failed (exit ${result.exitCode})',
        stderr: result.stderr,
      );
    }

    final worktree = Worktree(
      id: _uuid.v4(),
      projectId: project.id,
      name: slug,
      branch: branch,
      path: path,
      createdAt: _now(),
      status: WorktreeStatus.active,
    );
    await _projectRepository.addWorktree(worktree);
    return worktree;
  }

  Future<void> remove({
    required Project project,
    required Worktree worktree,
    required bool deleteBranch,
  }) async {
    final removeResult = await _processRunner.run('git', <String>[
      'worktree',
      'remove',
      '--force',
      worktree.path,
    ], workingDirectory: project.repoPath);
    if (removeResult.exitCode != 0) {
      // Try to prune in case the directory is gone but git's metadata lingers.
      await _processRunner.run('git', const <String>[
        'worktree',
        'prune',
      ], workingDirectory: project.repoPath);
    }

    if (deleteBranch) {
      final branchResult = await _processRunner.run('git', <String>[
        'branch',
        '-D',
        worktree.branch,
      ], workingDirectory: project.repoPath);
      if (branchResult.exitCode != 0) {
        // Surface the failure but don't undo the worktree removal — the user
        // can clean up the leftover branch manually.
        throw WorktreeException(
          'git branch -D ${worktree.branch} failed',
          stderr: branchResult.stderr,
        );
      }
    }

    await _projectRepository.updateWorktree(
      worktree.copyWith(status: WorktreeStatus.removed),
    );
  }

  /// Cross-checks the on-disk state with the database and marks any worktrees
  /// the user removed manually as `removed`.
  Future<List<Worktree>> reconcile(Project project) async {
    final result = await _processRunner.run('git', const <String>[
      'worktree',
      'list',
      '--porcelain',
    ], workingDirectory: project.repoPath);
    final livePaths = <String>{};
    if (result.exitCode == 0) {
      for (final line in const LineSplitter().convert(result.stdout)) {
        if (line.startsWith('worktree ')) {
          livePaths.add(line.substring('worktree '.length).trim());
        }
      }
    }

    final stored = await _projectRepository.listWorktrees(project.id);
    final reconciled = <Worktree>[];
    for (final wt in stored) {
      if (wt.status == WorktreeStatus.active && !livePaths.contains(wt.path)) {
        final updated = wt.copyWith(status: WorktreeStatus.removed);
        await _projectRepository.updateWorktree(updated);
        reconciled.add(updated);
      } else {
        reconciled.add(wt);
      }
    }
    return reconciled;
  }

  String _repoSlug(Project project) {
    final base = p.basename(project.repoPath);
    final hash = _shortHash(project.repoPath);
    final cleaned = slugify(base);
    return '$cleaned-$hash';
  }

  static String _shortHash(String input) {
    // FNV-1a 32-bit hash. Stable across runs and good enough as a path
    // disambiguator for repo paths that share a basename.
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    final bytes = utf8.encode(input);
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'dart:convert';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class WorkspaceException implements Exception {
  WorkspaceException(this.message, {this.stderr});

  final String message;
  final String? stderr;

  @override
  String toString() {
    final stderr = this.stderr?.trim();
    if (stderr == null || stderr.isEmpty) {
      return message;
    }
    return '$message: $stderr';
  }
}

/// Resolves the on-disk root for Alera-managed workspaces. Linked workspaces
/// are implemented as Git worktrees under this root.
class WorkspaceRoot {
  WorkspaceRoot({this.override});

  final String? override;

  String resolve() {
    final explicit = override;
    if (explicit != null) {
      return explicit;
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw WorkspaceException('Cannot locate user home directory');
    }
    return p.join(home, '.alera', 'workspaces');
  }
}

class WorkspaceService {
  WorkspaceService({
    required WorkbenchRepository repository,
    required ProjectService projectService,
    required ProcessRunner processRunner,
    WorkspaceRoot? workspaceRoot,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _repository = repository,
       _projectService = projectService,
       _processRunner = processRunner,
       _workspaceRoot = workspaceRoot ?? WorkspaceRoot(),
       _uuid = uuid ?? const Uuid(),
       _now = now ?? _defaultNow;

  final WorkbenchRepository _repository;
  final ProjectService _projectService;
  final ProcessRunner _processRunner;
  final WorkspaceRoot _workspaceRoot;
  final Uuid _uuid;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  Future<List<String>> listSourceBranches(Project project) {
    if (!project.supportsLinkedWorkspaces) {
      return Future<List<String>>.value(const <String>[]);
    }
    return _projectService.listGitBranches(project.repoPath);
  }

  Future<Workspace> ensureMainWorkspace(Project project) async {
    final existing = await _repository.listWorkspaces(project.id);
    final branch = project.isGitRepository
        ? await _currentBranch(project.repoPath)
        : null;
    final now = _now();
    Workspace? mainWorkspace;
    for (final workspace in existing) {
      if (workspace.isMain) {
        mainWorkspace = workspace;
        break;
      }
    }
    final next =
        (mainWorkspace ??
                Workspace(
                  id: _uuid.v4(),
                  projectId: project.id,
                  name: 'Main',
                  branch: branch,
                  path: project.repoPath,
                  createdAt: now,
                  updatedAt: now,
                  kind: WorkspaceKind.main,
                  status: WorkspaceStatus.active,
                ))
            .copyWith(
              name: 'Main',
              branch: branch,
              path: project.repoPath,
              updatedAt: now,
              kind: WorkspaceKind.main,
              status: WorkspaceStatus.active,
              clearSourceBranch: true,
            );
    await _repository.upsertWorkspace(next);
    return next;
  }

  Future<Workspace> createLinkedWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    String? name,
  }) async {
    if (!project.supportsLinkedWorkspaces) {
      throw WorkspaceException(
        'Linked workspaces require a Git repository project',
      );
    }
    final normalizedSource = sourceBranch.trim();
    final normalizedBranch = newBranchName.trim();
    if (normalizedSource.isEmpty) {
      throw WorkspaceException('Source branch is required');
    }
    if (normalizedBranch.isEmpty) {
      throw WorkspaceException('New branch name is required');
    }

    await _validateBranchName(project, normalizedBranch);
    await _ensureSourceBranchExists(project, normalizedSource);
    await _ensureNewBranchDoesNotExist(project, normalizedBranch);

    final workspaces = await _repository.listWorkspaces(project.id);
    if (workspaces.any(
      (workspace) => workspace.isActive && workspace.branch == normalizedBranch,
    )) {
      throw WorkspaceException(
        'A workspace for branch "$normalizedBranch" already exists',
      );
    }

    final displayName = (name ?? normalizedBranch).trim();
    final pathSlug = _slugifyPathSegment(displayName);
    final workspacePath = _resolveWorkspacePath(project, pathSlug);
    if (workspaces.any(
      (workspace) =>
          workspace.isActive && p.equals(workspace.path, workspacePath),
    )) {
      throw WorkspaceException(
        'A workspace already exists at "$workspacePath"',
      );
    }

    final parent = Directory(p.dirname(workspacePath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    final result = await _processRunner.run('git', <String>[
      'worktree',
      'add',
      '-b',
      normalizedBranch,
      workspacePath,
      normalizedSource,
    ], workingDirectory: project.repoPath);
    if (result.exitCode != 0) {
      throw WorkspaceException(
        'git worktree add failed (exit ${result.exitCode})',
        stderr: result.stderr,
      );
    }

    final workspace = Workspace(
      id: _uuid.v4(),
      projectId: project.id,
      name: displayName,
      branch: normalizedBranch,
      path: workspacePath,
      createdAt: _now(),
      updatedAt: _now(),
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
      sourceBranch: normalizedSource,
    );
    await _repository.upsertWorkspace(workspace);
    return workspace;
  }

  Future<void> removeWorkspace({
    required Project project,
    required Workspace workspace,
    required bool deleteBranch,
  }) async {
    if (workspace.isMain) {
      throw WorkspaceException('The main workspace cannot be removed');
    }
    final removeResult = await _processRunner.run('git', <String>[
      'worktree',
      'remove',
      '--force',
      workspace.path,
    ], workingDirectory: project.repoPath);
    if (removeResult.exitCode != 0) {
      throw WorkspaceException(
        'git worktree remove failed (exit ${removeResult.exitCode})',
        stderr: removeResult.stderr,
      );
    }
    if (deleteBranch) {
      final branch = workspace.branch;
      if (branch == null || branch.isEmpty) {
        throw WorkspaceException('Workspace branch is required');
      }
      final branchResult = await _processRunner.run('git', <String>[
        'branch',
        '-D',
        branch,
      ], workingDirectory: project.repoPath);
      if (branchResult.exitCode != 0) {
        throw WorkspaceException(
          'git branch -D $branch failed',
          stderr: branchResult.stderr,
        );
      }
    }
    await _repository.removeWorkspace(workspace.id, cascadeTabs: true);
  }

  Future<List<Workspace>> reconcile(Project project) async {
    final mainWorkspace = await ensureMainWorkspace(project);
    if (!project.supportsLinkedWorkspaces) {
      final workspaces = await _repository.listWorkspaces(project.id);
      for (final workspace in workspaces) {
        if (workspace.id == mainWorkspace.id) {
          continue;
        }
        await _repository.removeWorkspace(workspace.id, cascadeTabs: true);
      }
      return _repository.listWorkspaces(project.id);
    }
    final liveWorktrees = await _listLiveWorktrees(project.repoPath);
    final workspaces = await _repository.listWorkspaces(project.id);
    // When `git worktree list` fails (null) or doesn't even report the main
    // worktree, the listing can't be trusted. Skip pruning so a transient git
    // failure never hard-deletes live workspaces.
    final canPrune =
        liveWorktrees != null &&
        liveWorktrees.containsKey(_canonicalPath(mainWorkspace.path));
    for (final workspace in workspaces) {
      if (workspace.id == mainWorkspace.id) {
        continue;
      }
      final live = liveWorktrees?[_canonicalPath(workspace.path)];
      if (live == null) {
        if (canPrune) {
          await _repository.removeWorkspace(workspace.id, cascadeTabs: true);
        }
        continue;
      }
      if (workspace.branch != live.branch || workspace.path != live.path) {
        await _repository.upsertWorkspace(
          workspace.copyWith(
            branch: live.branch,
            path: live.path,
            updatedAt: _now(),
          ),
        );
      }
    }
    return _repository.listWorkspaces(project.id);
  }

  Future<void> _validateBranchName(Project project, String branchName) async {
    final result = await _processRunner.run('git', <String>[
      'check-ref-format',
      '--branch',
      branchName,
    ], workingDirectory: project.repoPath);
    if (result.exitCode != 0) {
      throw WorkspaceException(
        'Invalid branch name "$branchName"',
        stderr: result.stderr,
      );
    }
  }

  Future<void> _ensureSourceBranchExists(Project project, String branch) async {
    final branches = await _projectService.listGitBranches(project.repoPath);
    if (!branches.contains(branch)) {
      throw WorkspaceException('Source branch "$branch" does not exist');
    }
  }

  Future<void> _ensureNewBranchDoesNotExist(
    Project project,
    String branchName,
  ) async {
    final result = await _processRunner.run('git', <String>[
      'rev-parse',
      '--verify',
      '--quiet',
      branchName,
    ], workingDirectory: project.repoPath);
    if (result.exitCode == 0) {
      throw WorkspaceException('Branch "$branchName" already exists');
    }
  }

  Future<String> _currentBranch(String repoPath) async {
    final result = await _processRunner.run('git', const <String>[
      'branch',
      '--show-current',
    ], workingDirectory: repoPath);
    final branch = result.stdout.trim();
    if (result.exitCode == 0 && branch.isNotEmpty) {
      return branch;
    }
    return 'HEAD';
  }

  Future<Map<String, ({String path, String branch})>?> _listLiveWorktrees(
    String repoPath,
  ) async {
    final result = await _processRunner.run('git', const <String>[
      'worktree',
      'list',
      '--porcelain',
    ], workingDirectory: repoPath);
    if (result.exitCode != 0) {
      return null;
    }
    final lines = const LineSplitter().convert(result.stdout);
    final entries = <String, ({String path, String branch})>{};
    String? currentPath;
    String currentBranch = 'HEAD';
    void flush() {
      final path = currentPath;
      if (path == null || path.isEmpty) {
        return;
      }
      entries[_canonicalPath(path)] = (path: path, branch: currentBranch);
    }

    for (final line in lines) {
      if (line.isEmpty) {
        flush();
        currentPath = null;
        currentBranch = 'HEAD';
        continue;
      }
      if (line.startsWith('worktree ')) {
        currentPath = line.substring('worktree '.length).trim();
        continue;
      }
      if (line.startsWith('branch ')) {
        final rawBranch = line.substring('branch '.length).trim();
        currentBranch = rawBranch.startsWith('refs/heads/')
            ? rawBranch.substring('refs/heads/'.length)
            : rawBranch;
      }
    }
    flush();
    return entries;
  }

  /// Resolves [path] to its real on-disk location so symlinked worktree roots
  /// (e.g. macOS `/var` -> `/private/var`) match git's reported paths. Falls
  /// back to a normalized string when the path no longer exists.
  String _canonicalPath(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } catch (_) {
      return p.normalize(path);
    }
  }

  String _resolveWorkspacePath(Project project, String slug) {
    final projectSlug = _slugifyPathSegment(p.basename(project.repoPath));
    return p.join(_workspaceRoot.resolve(), '$projectSlug-${project.id}', slug);
  }

  String _slugifyPathSegment(String input) {
    final normalized = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_/]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (normalized.isEmpty) {
      throw WorkspaceException('Workspace name must contain a letter or digit');
    }
    return normalized;
  }
}

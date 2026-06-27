import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/worktree_setup_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';
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
  factory WorkspaceRoot({String? override, Map<String, String>? environment}) {
    return WorkspaceRoot._(override, environment ?? Platform.environment);
  }

  WorkspaceRoot._(this.override, this._environment);

  final String? override;
  final Map<String, String> _environment;

  String resolve() {
    final explicit = override;
    if (explicit != null) {
      return explicit;
    }
    final home = _environment['HOME'] ?? _environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw WorkspaceException('Cannot locate user home directory');
    }
    return p.join(home, '.alera', 'workspaces');
  }
}

class WorkspaceService {
  factory WorkspaceService({
    required WorkbenchRepository repository,
    required ProjectService projectService,
    required GitBackend gitBackend,
    WorkspaceRoot? workspaceRoot,
    ProjectConfigReader? projectConfigReader,
    WorktreeSetupRunner? worktreeSetupRunner,
    Uuid? uuid,
    DateTime Function()? now,
  }) {
    return WorkspaceService._(
      repository,
      projectService,
      gitBackend,
      workspaceRoot ?? WorkspaceRoot(),
      projectConfigReader ?? const NoopProjectConfigReader(),
      worktreeSetupRunner ?? const NoopWorktreeSetupRunner(),
      uuid ?? const Uuid(),
      now ?? _defaultNow,
    );
  }

  WorkspaceService._(
    this._repository,
    this._projectService,
    this._gitBackend,
    this._workspaceRoot,
    this._projectConfigReader,
    this._worktreeSetupRunner,
    this._uuid,
    this._now,
  );

  final WorkbenchRepository _repository;
  final ProjectService _projectService;
  final GitBackend _gitBackend;
  final WorkspaceRoot _workspaceRoot;
  final ProjectConfigReader _projectConfigReader;
  final WorktreeSetupRunner _worktreeSetupRunner;
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
              branch: branch,
              path: project.repoPath,
              updatedAt: now,
              kind: WorkspaceKind.main,
              status: WorkspaceStatus.active,
              sourceBranch: null,
            );
    await _repository.upsertWorkspace(next);
    return next;
  }

  Future<Workspace> renameWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw WorkspaceException('Workspace name must not be empty');
    }
    final workspace = await _repository.findWorkspaceById(workspaceId);
    if (workspace == null) {
      throw WorkspaceException('Workspace not found: $workspaceId');
    }
    final next = workspace.copyWith(name: trimmedName, updatedAt: _now());
    await _repository.upsertWorkspace(next);
    return next;
  }

  Future<WorkspaceCreationResult> createLinkedWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    String? name,
  }) async {
    if (!project.supportsLinkedWorkspaces) {
      throw WorkspaceException(
        'Linked Workspaces Require a Git Repository Project',
      );
    }
    final normalizedSource = sourceBranch.trim();
    final normalizedBranch = newBranchName.trim();
    if (normalizedSource.isEmpty) {
      throw WorkspaceException('Source Branch Is Required');
    }
    if (normalizedBranch.isEmpty) {
      throw WorkspaceException('New Branch Name Is Required');
    }

    await _validateBranchName(normalizedBranch);
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

    try {
      await _gitBackend.createWorktree(
        repoPath: project.repoPath,
        newBranch: normalizedBranch,
        path: workspacePath,
        sourceBranch: normalizedSource,
      );
    } on GitException catch (error) {
      throw WorkspaceException(
        'git worktree add failed',
        stderr: error.context,
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
    final setupReport = await _runWorktreeSetup(
      project: project,
      workspace: workspace,
    );
    return WorkspaceCreationResult(
      workspace: workspace,
      setupReport: setupReport,
    );
  }

  Future<WorktreeSetupReport> _runWorktreeSetup({
    required Project project,
    required Workspace workspace,
  }) async {
    final effective = await _projectConfigReader.resolve(project);
    final error = effective.error;
    if (error != null) {
      return WorktreeSetupReport(
        steps: <WorktreeSetupStepReport>[
          WorktreeSetupStepReport(
            kind: WorktreeSetupStepKind.config,
            label: 'alera.toml',
            succeeded: false,
            message: error.toString(),
          ),
        ],
      );
    }
    return _worktreeSetupRunner.run(
      project: project,
      workspace: workspace,
      config: effective.config,
    );
  }

  Future<void> removeWorkspace({
    required Project project,
    required Workspace workspace,
    required bool deleteBranch,
  }) async {
    if (workspace.isMain) {
      throw WorkspaceException('The main workspace cannot be removed');
    }
    try {
      await _gitBackend.removeWorktree(
        repoPath: project.repoPath,
        path: workspace.path,
        force: true,
      );
    } on GitException catch (error) {
      throw WorkspaceException(
        'git worktree remove failed',
        stderr: error.context,
      );
    }
    if (deleteBranch) {
      final branch = workspace.branch;
      if (branch == null || branch.isEmpty) {
        throw WorkspaceException('Workspace Branch Is Required');
      }
      try {
        await _gitBackend.deleteBranch(
          repoPath: project.repoPath,
          branch: branch,
          force: true,
        );
      } on GitException catch (error) {
        throw WorkspaceException(
          'git branch -D $branch failed',
          stderr: error.context,
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

  Future<void> _validateBranchName(String branchName) async {
    final bool valid;
    try {
      valid = await _gitBackend.isValidBranchName(branchName);
    } on GitException catch (error) {
      throw WorkspaceException(
        'Invalid branch name "$branchName"',
        stderr: error.context,
      );
    }
    if (!valid) {
      throw WorkspaceException('Invalid branch name "$branchName"');
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
    final exists = await _gitBackend.branchExists(project.repoPath, branchName);
    if (exists) {
      throw WorkspaceException('Branch "$branchName" already exists');
    }
  }

  Future<String> _currentBranch(String repoPath) async {
    try {
      return await _gitBackend.currentBranch(repoPath);
    } on GitException {
      return 'HEAD';
    }
  }

  Future<Map<String, ({String path, String branch})>?> _listLiveWorktrees(
    String repoPath,
  ) async {
    final List<GitWorktreeEntry> liveEntries;
    try {
      liveEntries = await _gitBackend.listWorktrees(repoPath);
    } on GitException {
      return null;
    }
    final entries = <String, ({String path, String branch})>{};
    for (final entry in liveEntries) {
      if (entry.path.isEmpty) {
        continue;
      }
      entries[_canonicalPath(entry.path)] = (
        path: entry.path,
        branch: entry.branch,
      );
    }
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

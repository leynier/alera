import 'package:alera/src/rust/api/git.dart' as rust;
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';

/// [GitBackend] backed by the Rust crate through flutter_rust_bridge. This is
/// the only place that knows about the generated bridge types; it translates
/// the native `GitError` into a domain [GitException] and the native worktree
/// records into [GitWorktreeEntry].
class RustGitBackend implements GitBackend {
  const RustGitBackend();

  @override
  Future<bool> isGitRepository(String path) =>
      _guard(() => rust.isGitRepository(path: path));

  @override
  Future<List<String>> listBranches(String path) =>
      _guard(() => rust.listBranches(path: path));

  @override
  Future<String> currentBranch(String path) =>
      _guard(() => rust.currentBranch(path: path));

  @override
  Future<bool> branchExists(String repoPath, String branch) =>
      _guard(() => rust.branchExists(repoPath: repoPath, branch: branch));

  @override
  Future<bool> isValidBranchName(String name) =>
      _guard(() => rust.isValidBranchName(name: name));

  @override
  Future<void> createWorktree({
    required String repoPath,
    required String newBranch,
    required String path,
    required String sourceBranch,
  }) => _guard(
    () => rust.createWorktree(
      repoPath: repoPath,
      newBranch: newBranch,
      path: path,
      sourceBranch: sourceBranch,
    ),
  );

  @override
  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  }) => _guard(
    () => rust.removeWorktree(repoPath: repoPath, path: path, force: force),
  );

  @override
  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  }) => _guard(
    () => rust.deleteBranch(repoPath: repoPath, branch: branch, force: force),
  );

  @override
  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath) =>
      _guard(() async {
        final entries = await rust.listWorktrees(repoPath: repoPath);
        return entries
            .map(
              (entry) =>
                  GitWorktreeEntry(path: entry.path, branch: entry.branch),
            )
            .toList(growable: false);
      });

  @override
  Future<void> clone({required String url, required String destinationPath}) =>
      _guard(
        () => rust.cloneRepository(url: url, destinationPath: destinationPath),
      );

  @override
  Future<GitStatusResult> status(String path) => _guard(() async {
    final result = await rust.gitStatus(path: path);
    return _toStatusResult(result);
  });

  @override
  Future<GitStatusResult> statusForPath({
    required String path,
    required String filePath,
  }) => _guard(() async {
    final result = await rust.gitStatusForPath(path: path, filePath: filePath);
    return _toStatusResult(result);
  });

  @override
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) => _guard(() async {
    final result = await rust.gitDiff(
      path: path,
      filePath: filePath,
      area: _toRustArea(area),
    );
    return _toDiffResult(result);
  });

  @override
  Future<GitDiffResult> diffAll({required String path, String? filePath}) =>
      _guard(() async {
        final result = await rust.gitDiffAll(path: path, filePath: filePath);
        return _toDiffResult(result);
      });

  @override
  Future<GitRepositoryState> repositoryState(String path) => _guard(() async {
    final state = await rust.gitRepositoryState(path: path);
    return GitRepositoryState(
      branch: state.branch,
      upstream: state.upstream,
      ahead: state.ahead,
      behind: state.behind,
      hasConflicts: state.hasConflicts,
    );
  });

  @override
  Future<void> stage({required String path, String? filePath}) =>
      _guard(() => rust.gitStage(path: path, filePath: filePath));

  @override
  Future<void> unstage({required String path, String? filePath}) =>
      _guard(() => rust.gitUnstage(path: path, filePath: filePath));

  @override
  Future<void> discard({required String path, String? filePath}) =>
      _guard(() => rust.gitDiscard(path: path, filePath: filePath));

  @override
  Future<String> commit({required String path, required String message}) =>
      _guard(() => rust.gitCommit(path: path, message: message));

  @override
  Future<void> fetch(String path) => _guard(() => rust.gitFetch(path: path));

  @override
  Future<void> pull(String path) => _guard(() => rust.gitPull(path: path));

  @override
  Future<void> push(String path) => _guard(() => rust.gitPush(path: path));

  @override
  Future<List<GitStashEntry>> listStashes(String path) => _guard(() async {
    final entries = await rust.gitListStashes(path: path);
    return entries
        .map(
          (entry) => GitStashEntry(
            index: entry.index,
            reference: entry.reference,
            message: entry.message,
            oid: entry.oid,
          ),
        )
        .toList(growable: false);
  });

  @override
  Future<void> stash(String path) => _guard(() => rust.gitStash(path: path));

  @override
  Future<void> stashPop({required String path, required int stashIndex}) =>
      _guard(() => rust.gitStashPop(path: path, stashIndex: stashIndex));

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on rust.GitError catch (error) {
      throw _toException(error);
    }
  }

  GitException _toException(rust.GitError error) {
    final context = error.context;
    return switch (error.kind) {
      rust.GitErrorKind.notARepository => NotARepositoryException(context),
      rust.GitErrorKind.accessDenied => AccessDeniedException(context),
      rust.GitErrorKind.branchNotFound => BranchNotFoundException(context),
      rust.GitErrorKind.branchAlreadyExists => BranchAlreadyExistsException(
        context,
      ),
      rust.GitErrorKind.invalidBranchName => InvalidBranchNameException(
        context,
      ),
      rust.GitErrorKind.worktreeAlreadyExists => WorktreeAlreadyExistsException(
        context,
      ),
      rust.GitErrorKind.worktreeNotFound => WorktreeNotFoundException(context),
      rust.GitErrorKind.cloneFailed => CloneFailedException(context),
      rust.GitErrorKind.gitCli => GitCliException(context),
      rust.GitErrorKind.detachedHead => DetachedHeadException(context),
      rust.GitErrorKind.noUpstream => NoUpstreamException(context),
      rust.GitErrorKind.remoteNotFound => RemoteNotFoundException(context),
      rust.GitErrorKind.nothingToCommit => NothingToCommitException(context),
      rust.GitErrorKind.workspaceScope => WorkspaceScopeException(context),
      rust.GitErrorKind.missingIdentity => MissingIdentityException(context),
      rust.GitErrorKind.conflict => GitConflictException(context),
      rust.GitErrorKind.internal => GitInternalException(context),
    };
  }

  GitChangeEntry _toChangeEntry(rust.GitChangeEntry entry) {
    return GitChangeEntry(
      path: entry.path,
      oldPath: entry.oldPath,
      area: _toArea(entry.area),
      status: _toStatus(entry.status),
      added: entry.added,
      removed: entry.removed,
      isBinary: entry.isBinary,
      isLarge: entry.isLarge,
    );
  }

  GitStatusResult _toStatusResult(rust.GitStatusResult result) {
    return GitStatusResult(
      entries: result.entries.map(_toChangeEntry).toList(growable: false),
      groups: result.groups.map(_toChangeGroup).toList(growable: false),
    );
  }

  GitChangeGroup _toChangeGroup(rust.GitChangeGroup group) {
    return GitChangeGroup(
      area: _toArea(group.area),
      entries: group.entries.map(_toChangeEntry).toList(growable: false),
      treeRows: group.treeRows.map(_toTreeRow).toList(growable: false),
    );
  }

  GitChangeTreeRow _toTreeRow(rust.GitChangeTreeRow row) {
    return GitChangeTreeRow(
      kind: _toTreeRowKind(row.kind),
      name: row.name,
      path: row.path,
      depth: row.depth,
      fileCount: row.fileCount,
      entry: row.entry == null ? null : _toChangeEntry(row.entry!),
    );
  }

  GitDiffResult _toDiffResult(rust.GitDiffResult result) {
    return GitDiffResult(
      truncated: result.truncated,
      files: result.files
          .map(
            (file) => GitDiffFile(
              path: file.path,
              oldPath: file.oldPath,
              area: _toArea(file.area),
              status: _toStatus(file.status),
              lines: file.lines.map(_toDiffLine).toList(growable: false),
              added: file.added,
              removed: file.removed,
              isBinary: file.isBinary,
              isLarge: file.isLarge,
              truncated: file.truncated,
              linePreviewTruncated: file.linePreviewTruncated,
            ),
          )
          .toList(growable: false),
    );
  }

  GitDiffLine _toDiffLine(rust.GitDiffLine line) {
    return GitDiffLine(text: line.text, kind: _toDiffLineKind(line.kind));
  }

  GitChangeArea _toArea(rust.GitChangeArea area) {
    return switch (area) {
      rust.GitChangeArea.untracked => GitChangeArea.untracked,
      rust.GitChangeArea.unstaged => GitChangeArea.unstaged,
      rust.GitChangeArea.staged => GitChangeArea.staged,
    };
  }

  rust.GitChangeArea _toRustArea(GitChangeArea area) {
    return switch (area) {
      GitChangeArea.untracked => rust.GitChangeArea.untracked,
      GitChangeArea.unstaged => rust.GitChangeArea.unstaged,
      GitChangeArea.staged => rust.GitChangeArea.staged,
    };
  }

  GitChangeTreeRowKind _toTreeRowKind(rust.GitChangeTreeRowKind kind) {
    return switch (kind) {
      rust.GitChangeTreeRowKind.directory => GitChangeTreeRowKind.directory,
      rust.GitChangeTreeRowKind.file => GitChangeTreeRowKind.file,
    };
  }

  GitDiffLineKind _toDiffLineKind(rust.GitDiffLineKind kind) {
    return switch (kind) {
      rust.GitDiffLineKind.addition => GitDiffLineKind.addition,
      rust.GitDiffLineKind.deletion => GitDiffLineKind.deletion,
      rust.GitDiffLineKind.hunk => GitDiffLineKind.hunk,
      rust.GitDiffLineKind.header => GitDiffLineKind.header,
      rust.GitDiffLineKind.context => GitDiffLineKind.context,
    };
  }

  GitChangeStatus _toStatus(rust.GitChangeStatus status) {
    return switch (status) {
      rust.GitChangeStatus.modified => GitChangeStatus.modified,
      rust.GitChangeStatus.added => GitChangeStatus.added,
      rust.GitChangeStatus.deleted => GitChangeStatus.deleted,
      rust.GitChangeStatus.renamed => GitChangeStatus.renamed,
      rust.GitChangeStatus.copied => GitChangeStatus.copied,
      rust.GitChangeStatus.untracked => GitChangeStatus.untracked,
    };
  }
}

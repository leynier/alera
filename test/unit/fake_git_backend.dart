import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';

/// A recorded [GitBackend] invocation, used by tests to assert which git
/// operations a service performed and with which arguments.
class GitBackendCall {
  GitBackendCall(this.method, [this.args = const <String, Object?>{}]);

  final String method;
  final Map<String, Object?> args;
}

/// In-memory [GitBackend] for unit tests. Field names mirror the behaviours the
/// previous `ProcessRunner` fakes configured, so tests can program repository
/// state and failure injection without spawning git.
class FakeGitBackend implements GitBackend {
  final List<GitBackendCall> calls = <GitBackendCall>[];

  /// Result for [isGitRepository] when [isRepositoryError] is null.
  bool isRepository = true;

  /// When set, [isGitRepository] throws this instead of returning a value.
  GitException? isRepositoryError;

  /// Branches reported by [listBranches] and treated as existing by
  /// [branchExists]. The real backend sorts and de-duplicates; the fake does
  /// too so callers observe the same shape.
  List<String> sourceBranches = <String>['main'];

  /// When set, [listBranches] throws instead of returning a value.
  bool listBranchesFails = false;

  /// Value returned by [currentBranch] unless [headBranchFails] is set.
  String headBranch = 'main';

  /// When set, [currentBranch] throws (callers fall back to `HEAD`).
  bool headBranchFails = false;

  /// Names rejected by [isValidBranchName].
  final Set<String> invalidBranchNames = <String>{};

  /// When set, [listWorktrees] always reports the queried repo path as the main
  /// work tree (branch [headBranch]), mirroring how `git worktree list` always
  /// includes the main checkout.
  bool includeQueriedRepoAsMain = false;

  /// Live worktrees reported by [listWorktrees], keyed by path → branch.
  Map<String, String> liveBranchByPath = <String, String>{};

  /// When set, [listWorktrees] throws (callers treat the listing as untrusted).
  bool worktreeListFails = false;

  /// New-branch names whose [createWorktree] should fail.
  final Set<String> failingWorktreeAddBranches = <String>{};

  /// Worktree paths whose [removeWorktree] should fail.
  final Set<String> failingWorktreeRemovePaths = <String>{};

  /// Branch names whose [deleteBranch] should fail.
  final Set<String> failingBranchDeletes = <String>{};

  /// When set, [clone] throws [cloneError].
  bool cloneFails = false;
  GitException cloneError = const CloneFailedException(
    'fatal: could not clone',
  );

  /// Side effect invoked by a successful [clone] (e.g. to materialise the
  /// destination on disk).
  void Function(String url, String destinationPath)? onClone;

  GitStatusResult gitStatusResult = const GitStatusResult(entries: []);
  GitDiffResult gitDiffResult = const GitDiffResult(files: []);
  GitDiffResult gitDiffAllResult = const GitDiffResult(files: []);
  GitRepositoryState gitRepositoryStateResult = const GitRepositoryState(
    branch: 'main',
  );
  List<GitStashEntry> gitStashEntries = const <GitStashEntry>[];
  String gitCommitOid = 'abc123';

  GitException? statusError;
  GitException? stageError;
  GitException? stageAreaError;
  GitException? unstageError;
  GitException? unstageAreaError;
  GitException? discardError;
  GitException? discardAreaError;
  GitException? commitError;
  GitException? fetchError;
  GitException? pullError;
  GitException? pushError;
  GitException? stashError;
  GitException? stashPopError;

  @override
  Future<bool> isGitRepository(String path) async {
    calls.add(
      GitBackendCall('isGitRepository', <String, Object?>{'path': path}),
    );
    final error = isRepositoryError;
    if (error != null) {
      throw error;
    }
    return isRepository;
  }

  @override
  Future<List<String>> listBranches(String path) async {
    calls.add(GitBackendCall('listBranches', <String, Object?>{'path': path}));
    if (listBranchesFails) {
      throw const GitInternalException('listBranches failed');
    }
    final unique = sourceBranches.toSet().toList()..sort();
    return unique;
  }

  @override
  Future<String> currentBranch(String path) async {
    calls.add(GitBackendCall('currentBranch', <String, Object?>{'path': path}));
    if (headBranchFails) {
      throw const GitInternalException('no head');
    }
    return headBranch;
  }

  @override
  Future<bool> branchExists(String repoPath, String branch) async {
    calls.add(
      GitBackendCall('branchExists', <String, Object?>{
        'repoPath': repoPath,
        'branch': branch,
      }),
    );
    return sourceBranches.contains(branch);
  }

  @override
  Future<bool> isValidBranchName(String name) async {
    calls.add(
      GitBackendCall('isValidBranchName', <String, Object?>{'name': name}),
    );
    return !invalidBranchNames.contains(name);
  }

  @override
  Future<void> createWorktree({
    required String repoPath,
    required String newBranch,
    required String path,
    required String sourceBranch,
  }) async {
    calls.add(
      GitBackendCall('createWorktree', <String, Object?>{
        'repoPath': repoPath,
        'newBranch': newBranch,
        'path': path,
        'sourceBranch': sourceBranch,
      }),
    );
    if (failingWorktreeAddBranches.contains(newBranch)) {
      throw const GitInternalException('add failed');
    }
  }

  @override
  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  }) async {
    calls.add(
      GitBackendCall('removeWorktree', <String, Object?>{
        'repoPath': repoPath,
        'path': path,
        'force': force,
      }),
    );
    if (failingWorktreeRemovePaths.contains(path)) {
      throw const GitInternalException('remove failed');
    }
  }

  @override
  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  }) async {
    calls.add(
      GitBackendCall('deleteBranch', <String, Object?>{
        'repoPath': repoPath,
        'branch': branch,
        'force': force,
      }),
    );
    if (failingBranchDeletes.contains(branch)) {
      throw const GitInternalException('delete failed');
    }
  }

  @override
  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath) async {
    calls.add(
      GitBackendCall('listWorktrees', <String, Object?>{'repoPath': repoPath}),
    );
    if (worktreeListFails) {
      throw const GitInternalException('not a git repository');
    }
    return <GitWorktreeEntry>[
      if (includeQueriedRepoAsMain)
        GitWorktreeEntry(path: repoPath, branch: headBranch),
      for (final entry in liveBranchByPath.entries)
        GitWorktreeEntry(path: entry.key, branch: entry.value),
    ];
  }

  @override
  Future<void> clone({
    required String url,
    required String destinationPath,
  }) async {
    calls.add(
      GitBackendCall('clone', <String, Object?>{
        'url': url,
        'destinationPath': destinationPath,
      }),
    );
    if (cloneFails) {
      throw cloneError;
    }
    onClone?.call(url, destinationPath);
  }

  @override
  Future<GitStatusResult> status(String path) async {
    calls.add(GitBackendCall('status', <String, Object?>{'path': path}));
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return gitStatusResult;
  }

  @override
  Future<GitStatusResult> statusForPath({
    required String path,
    required String filePath,
  }) async {
    calls.add(
      GitBackendCall('statusForPath', <String, Object?>{
        'path': path,
        'filePath': filePath,
      }),
    );
    return GitStatusResult(
      entries: gitStatusResult.entriesForPath(filePath),
      groups: GitChangeGroup.fromEntries(
        gitStatusResult.entriesForPath(filePath),
      ),
    );
  }

  @override
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) async {
    calls.add(
      GitBackendCall('diff', <String, Object?>{
        'path': path,
        'filePath': filePath,
        'area': area,
      }),
    );
    return gitDiffResult;
  }

  @override
  Future<GitDiffResult> diffAll({
    required String path,
    String? filePath,
  }) async {
    calls.add(
      GitBackendCall('diffAll', <String, Object?>{
        'path': path,
        'filePath': filePath,
      }),
    );
    return gitDiffAllResult;
  }

  @override
  Future<GitRepositoryState> repositoryState(String path) async {
    calls.add(
      GitBackendCall('repositoryState', <String, Object?>{'path': path}),
    );
    return gitRepositoryStateResult;
  }

  @override
  Future<void> stage({required String path, String? filePath}) async {
    calls.add(
      GitBackendCall('stage', <String, Object?>{
        'path': path,
        'filePath': filePath,
      }),
    );
    final error = stageError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> stageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) async {
    calls.add(
      GitBackendCall('stageArea', <String, Object?>{
        'path': path,
        'area': area,
        'filePath': filePath,
      }),
    );
    final error = stageAreaError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> unstage({required String path, String? filePath}) async {
    calls.add(
      GitBackendCall('unstage', <String, Object?>{
        'path': path,
        'filePath': filePath,
      }),
    );
    final error = unstageError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> unstageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) async {
    calls.add(
      GitBackendCall('unstageArea', <String, Object?>{
        'path': path,
        'area': area,
        'filePath': filePath,
      }),
    );
    final error = unstageAreaError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> discard({required String path, String? filePath}) async {
    calls.add(
      GitBackendCall('discard', <String, Object?>{
        'path': path,
        'filePath': filePath,
      }),
    );
    final error = discardError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> discardArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) async {
    calls.add(
      GitBackendCall('discardArea', <String, Object?>{
        'path': path,
        'area': area,
        'filePath': filePath,
      }),
    );
    final error = discardAreaError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<String> commit({required String path, required String message}) async {
    calls.add(
      GitBackendCall('commit', <String, Object?>{
        'path': path,
        'message': message,
      }),
    );
    final error = commitError;
    if (error != null) {
      throw error;
    }
    return gitCommitOid;
  }

  @override
  Future<void> fetch(String path) async {
    calls.add(GitBackendCall('fetch', <String, Object?>{'path': path}));
    final error = fetchError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> pull(String path) async {
    calls.add(GitBackendCall('pull', <String, Object?>{'path': path}));
    final error = pullError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> push(String path) async {
    calls.add(GitBackendCall('push', <String, Object?>{'path': path}));
    final error = pushError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<List<GitStashEntry>> listStashes(String path) async {
    calls.add(GitBackendCall('listStashes', <String, Object?>{'path': path}));
    return gitStashEntries;
  }

  @override
  Future<void> stash(String path) async {
    calls.add(GitBackendCall('stash', <String, Object?>{'path': path}));
    final error = stashError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> stashPop({required String path, required int stashIndex}) async {
    calls.add(
      GitBackendCall('stashPop', <String, Object?>{
        'path': path,
        'stashIndex': stashIndex,
      }),
    );
    final error = stashPopError;
    if (error != null) {
      throw error;
    }
  }
}

import 'dart:typed_data';

import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_explorer_status.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';

/// Resolves the backend for a checkout path: the remote runtime backend when
/// the path belongs to a workspace on another host, null otherwise.
typedef RemoteGitBackendResolver = GitBackend? Function(String path);

/// [GitBackend] that answers for every checkout the app knows about. A path
/// inside a remote workspace goes to that host's runtime backend; anything
/// else goes to the local bridge. Callers keep passing the path they already
/// have, so Source Control, diffs, history and the explorer work the same for
/// a remote checkout without branching on the workspace.
///
/// Operations without a repository path (`isValidBranchName`, `clone`) are
/// local: the first is pure, the second targets a local destination.
class const HostRoutedGitBackend({
  required final GitBackend local,
  required final RemoteGitBackendResolver remoteFor,
}) implements GitBackend {
  GitBackend _for(String path) => remoteFor(path) ?? local;

  @override
  Future<bool> isGitRepository(String path) => _for(path).isGitRepository(path);

  @override
  Future<List<String>> listBranches(String path) =>
      _for(path).listBranches(path);

  @override
  Future<String> currentBranch(String path) => _for(path).currentBranch(path);

  @override
  Future<String> defaultBranch(String path) => _for(path).defaultBranch(path);

  @override
  Future<void> createAndCheckoutBranch({
    required String path,
    required String branch,
    String? expectedHead,
    String? expectedOid,
  }) => _for(path).createAndCheckoutBranch(
    path: path,
    branch: branch,
    expectedHead: expectedHead,
    expectedOid: expectedOid,
  );

  @override
  Future<void> resetBranchToRef({
    required String path,
    required String branch,
    required String targetRef,
    String? expectedOid,
  }) => _for(path).resetBranchToRef(
    path: path,
    branch: branch,
    targetRef: targetRef,
    expectedOid: expectedOid,
  );

  @override
  Future<void> checkoutBranch({required String path, required String branch}) =>
      _for(path).checkoutBranch(path: path, branch: branch);

  @override
  Future<bool> branchExists(String repoPath, String branch) =>
      _for(repoPath).branchExists(repoPath, branch);

  @override
  Future<bool> isAncestor({
    required String path,
    required String ancestorRef,
    required String descendantRef,
  }) => _for(path).isAncestor(
    path: path,
    ancestorRef: ancestorRef,
    descendantRef: descendantRef,
  );

  @override
  Future<bool> isValidBranchName(String name) => local.isValidBranchName(name);

  @override
  Future<void> createWorktree({
    required String repoPath,
    required String targetBranch,
    required String path,
    required String sourceBranch,
    bool reuseExistingBranch = false,
  }) => _for(repoPath).createWorktree(
    repoPath: repoPath,
    targetBranch: targetBranch,
    path: path,
    sourceBranch: sourceBranch,
    reuseExistingBranch: reuseExistingBranch,
  );

  @override
  Future<void> refreshSourceBranch({
    required String repoPath,
    required String sourceBranch,
  }) =>
      _for(repoPath)
          .refreshSourceBranch(repoPath: repoPath, sourceBranch: sourceBranch);

  @override
  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  }) =>
      _for(repoPath)
          .removeWorktree(repoPath: repoPath, path: path, force: force);

  @override
  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  }) =>
      _for(repoPath)
          .deleteBranch(repoPath: repoPath, branch: branch, force: force);

  @override
  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath) =>
      _for(repoPath).listWorktrees(repoPath);

  @override
  Future<List<GitRemote>> listRemotes(String path) =>
      _for(path).listRemotes(path);

  @override
  Future<void> clone({required String url, required String destinationPath}) =>
      local.clone(url: url, destinationPath: destinationPath);

  @override
  Future<GitStatusResult> status(String path) => _for(path).status(path);

  @override
  Future<GitExplorerStatusSnapshot> explorerStatusSnapshot(String path) =>
      _for(path).explorerStatusSnapshot(path);

  @override
  Future<GitStatusResult> statusForPath({
    required String path,
    required String filePath,
  }) => _for(path).statusForPath(path: path, filePath: filePath);

  @override
  Future<GitStatusResult> submoduleStatus({
    required String path,
    required String submodulePath,
    required GitChangeArea area,
  }) => _for(path)
      .submoduleStatus(path: path, submodulePath: submodulePath, area: area);

  @override
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) => _for(path).diff(path: path, filePath: filePath, area: area);

  @override
  Future<GitDiffResult> diffAll({required String path, String? filePath}) =>
      _for(path).diffAll(path: path, filePath: filePath);

  @override
  Future<Uint8List> readingDiffPatch({
    required String path,
    String? filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    String? baseRef,
  }) => _for(path).readingDiffPatch(
    path: path,
    filePath: filePath,
    oldPath: oldPath,
    area: area,
    commitOid: commitOid,
    parentOid: parentOid,
    baseRef: baseRef,
  );

  @override
  Future<Uint8List?> diffBlobBytes({
    required String path,
    required String filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    required bool oldSide,
  }) => _for(path).diffBlobBytes(
    path: path,
    filePath: filePath,
    oldPath: oldPath,
    area: area,
    commitOid: commitOid,
    parentOid: parentOid,
    oldSide: oldSide,
  );

  @override
  Future<GitHistoryResult> history(
    String path, {
    int? limit,
    String? baseRef,
  }) => _for(path).history(path, limit: limit, baseRef: baseRef);

  @override
  Future<GitCommitCompareResult> commitCompare({
    required String path,
    required String commitId,
  }) => _for(path).commitCompare(path: path, commitId: commitId);

  @override
  Future<GitDiffResult> commitDiff({
    required String path,
    required String commitOid,
    String? parentOid,
    String? filePath,
    String? oldPath,
  }) => _for(path).commitDiff(
    path: path,
    commitOid: commitOid,
    parentOid: parentOid,
    filePath: filePath,
    oldPath: oldPath,
  );

  @override
  Future<GitRangeContext> rangeContext(
    String path, {
    required String baseRef,
    int commitLimit = 40,
    String? headRef,
  }) => _for(path).rangeContext(
    path,
    baseRef: baseRef,
    commitLimit: commitLimit,
    headRef: headRef,
  );

  @override
  Future<GitRepositoryState> repositoryState(String path) =>
      _for(path).repositoryState(path);

  @override
  Future<void> stage({required String path, String? filePath}) =>
      _for(path).stage(path: path, filePath: filePath);

  @override
  Future<void> stageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) => _for(path).stageArea(path: path, area: area, filePath: filePath);

  @override
  Future<void> unstage({required String path, String? filePath}) =>
      _for(path).unstage(path: path, filePath: filePath);

  @override
  Future<void> unstageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) => _for(path).unstageArea(path: path, area: area, filePath: filePath);

  @override
  Future<void> discard({required String path, String? filePath}) =>
      _for(path).discard(path: path, filePath: filePath);

  @override
  Future<void> discardArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) => _for(path).discardArea(path: path, area: area, filePath: filePath);

  @override
  Future<String> commit({required String path, required String message}) =>
      _for(path).commit(path: path, message: message);

  @override
  Future<String> amendCommit({required String path, required String message}) =>
      _for(path).amendCommit(path: path, message: message);

  @override
  Future<void> fetch(String path) => _for(path).fetch(path);

  @override
  Future<GitHostedReviewRange> fetchHostedReviewRange({
    required String path,
    required String remote,
    required String baseBranch,
    required String headSha,
    String? headRemote,
    String? comparisonBaseSha,
    String? mergeCommitSha,
    String? reviewRef,
  }) => _for(path).fetchHostedReviewRange(
    path: path,
    remote: remote,
    baseBranch: baseBranch,
    headSha: headSha,
    headRemote: headRemote,
    comparisonBaseSha: comparisonBaseSha,
    mergeCommitSha: mergeCommitSha,
    reviewRef: reviewRef,
  );

  @override
  Future<void> persistHostedReviewRange({
    required String path,
    required String retentionId,
  }) =>
      _for(path).persistHostedReviewRange(path: path, retentionId: retentionId);

  @override
  Future<void> releaseHostedReviewRange({
    required String path,
    required String retentionId,
  }) =>
      _for(path).releaseHostedReviewRange(path: path, retentionId: retentionId);

  @override
  Future<void> pull(String path) => _for(path).pull(path);

  @override
  Future<void> push(String path) => _for(path).push(path);

  @override
  Future<List<GitStashEntry>> listStashes(String path) =>
      _for(path).listStashes(path);

  @override
  Future<void> stash(String path) => _for(path).stash(path);

  @override
  Future<void> stashPop({required String path, required int stashIndex}) =>
      _for(path).stashPop(path: path, stashIndex: stashIndex);
}

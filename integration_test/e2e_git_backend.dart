import 'dart:typed_data';

import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_explorer_status.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';

/// Inert [GitBackend] so the smoke flow never touches a real repository.
class E2eGitBackend implements GitBackend {
  const E2eGitBackend();

  @override
  Future<bool> isGitRepository(String path) async => false;

  @override
  Future<List<String>> listBranches(String path) async => const <String>[];

  @override
  Future<String> currentBranch(String path) async => 'HEAD';

  @override
  Future<bool> branchExists(String repoPath, String branch) async => false;

  @override
  Future<bool> isAncestor({
    required String path,
    required String ancestorRef,
    required String descendantRef,
  }) async => false;

  @override
  Future<bool> isValidBranchName(String name) async => true;

  @override
  Future<void> createWorktree({
    required String repoPath,
    required String targetBranch,
    required String path,
    required String sourceBranch,
    bool reuseExistingBranch = false,
  }) async {}

  @override
  Future<void> refreshSourceBranch({
    required String repoPath,
    required String sourceBranch,
  }) async {}

  @override
  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  }) async {}

  @override
  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  }) async {}

  @override
  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath) async =>
      const <GitWorktreeEntry>[];

  @override
  Future<List<GitRemote>> listRemotes(String path) async => const <GitRemote>[];

  @override
  Future<void> clone({
    required String url,
    required String destinationPath,
  }) async {}

  @override
  Future<GitStatusResult> status(String path) async =>
      const GitStatusResult(entries: <GitChangeEntry>[]);

  @override
  Future<GitExplorerStatusSnapshot> explorerStatusSnapshot(String path) async =>
      const GitExplorerStatusSnapshot.empty();

  @override
  Future<GitStatusResult> statusForPath({
    required String path,
    required String filePath,
  }) async => const GitStatusResult(entries: <GitChangeEntry>[]);

  @override
  Future<GitStatusResult> submoduleStatus({
    required String path,
    required String submodulePath,
    required GitChangeArea area,
  }) async => const GitStatusResult(entries: <GitChangeEntry>[]);

  @override
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) async => const GitDiffResult(files: <GitDiffFile>[]);

  @override
  Future<GitDiffResult> diffAll({
    required String path,
    String? filePath,
  }) async => const GitDiffResult(files: <GitDiffFile>[]);

  @override
  Future<Uint8List> readingDiffPatch({
    required String path,
    String? filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    String? baseRef,
  }) async => Uint8List(0);

  @override
  Future<Uint8List?> diffBlobBytes({
    required String path,
    required String filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    required bool oldSide,
  }) async => null;

  @override
  Future<GitHistoryResult> history(
    String path, {
    int? limit,
    String? baseRef,
  }) async => GitHistoryResult(
    items: const <GitHistoryItem>[],
    hasIncomingChanges: false,
    hasOutgoingChanges: false,
    hasMore: false,
    limit: limit ?? 50,
  );

  @override
  Future<GitCommitCompareResult> commitCompare({
    required String path,
    required String commitId,
  }) async => GitCommitCompareResult(
    summary: GitCommitCompareSummary(
      commitOid: commitId,
      parentOid: null,
      compareRef: commitId,
      baseRef: 'Parent',
      changedFiles: 0,
      status: GitCommitCompareStatus.invalidCommit,
      errorMessage: 'Commit Not Available',
    ),
    entries: const <GitCommitChangeEntry>[],
  );

  @override
  Future<GitDiffResult> commitDiff({
    required String path,
    required String commitOid,
    String? parentOid,
    String? filePath,
    String? oldPath,
  }) async => const GitDiffResult(files: <GitDiffFile>[]);

  @override
  Future<GitRangeContext> rangeContext(
    String path, {
    required String baseRef,
    int commitLimit = 40,
    String? headRef,
  }) async => GitRangeContext(
    baseRef: baseRef,
    commits: const <GitRangeCommit>[],
    files: const <GitRangeFile>[],
    patch: '',
  );

  @override
  Future<GitRepositoryState> repositoryState(String path) async =>
      const GitRepositoryState(branch: 'HEAD');

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
  }) async => GitHostedReviewRange(
    baseOid: baseBranch,
    headOid: headSha,
    retentionId: '00000000000000000000000000000001',
  );

  @override
  Future<void> releaseHostedReviewRange({
    required String path,
    required String retentionId,
  }) async {}

  @override
  Future<void> persistHostedReviewRange({
    required String path,
    required String retentionId,
  }) async {}

  @override
  Future<void> stage({required String path, String? filePath}) async {}

  @override
  Future<void> stageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) async {}

  @override
  Future<void> unstage({required String path, String? filePath}) async {}

  @override
  Future<void> unstageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) async {}

  @override
  Future<void> discard({required String path, String? filePath}) async {}

  @override
  Future<void> discardArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) async {}

  @override
  Future<String> commit({
    required String path,
    required String message,
  }) async => 'e2e';

  @override
  Future<String> amendCommit({
    required String path,
    required String message,
  }) async => 'e2e';

  @override
  Future<void> fetch(String path) async {}

  @override
  Future<void> pull(String path) async {}

  @override
  Future<void> push(String path) async {}

  @override
  Future<List<GitStashEntry>> listStashes(String path) async =>
      const <GitStashEntry>[];

  @override
  Future<void> stash(String path) async {}

  @override
  Future<void> stashPop({
    required String path,
    required int stashIndex,
  }) async {}
}

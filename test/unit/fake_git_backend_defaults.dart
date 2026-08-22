part of 'fake_git_backend.dart';

/// A recorded [GitBackend] invocation, used by tests to assert which git
/// operations a service performed and with which arguments.
class GitBackendCall {
  GitBackendCall(this.method, [this.args = const <String, Object?>{}]);

  final String method;
  final Map<String, Object?> args;
}

GitCommitCompareResult _defaultGitCommitCompareResult() =>
    const GitCommitCompareResult(
      summary: GitCommitCompareSummary(
        commitOid: 'abc123',
        parentOid: 'def456',
        compareRef: 'abc123',
        baseRef: 'def456',
        changedFiles: 0,
        status: GitCommitCompareStatus.ready,
      ),
      entries: <GitCommitChangeEntry>[],
    );

GitRangeContext _defaultGitRangeContext() => const GitRangeContext(
  baseRef: 'main',
  headOid: 'abc1234',
  headBranch: 'feature',
  commits: <GitRangeCommit>[
    GitRangeCommit(
      oid: 'abc1234',
      subject: 'feat: example',
      message: 'feat: example\n\nDetails',
    ),
  ],
  files: <GitRangeFile>[
    GitRangeFile(
      path: 'lib/foo.dart',
      status: GitChangeStatus.modified,
      added: 2,
      removed: 1,
    ),
  ],
  patch: 'diff --git a/lib/foo.dart b/lib/foo.dart\n+new line',
);

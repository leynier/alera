part of 'rust_git_backend.dart';

extension on RustGitBackend {
  GitDiffLineKind _toDiffLineKind(rust.GitDiffLineKind kind) {
    return switch (kind) {
      rust.GitDiffLineKind.addition => GitDiffLineKind.addition,
      rust.GitDiffLineKind.deletion => GitDiffLineKind.deletion,
      rust.GitDiffLineKind.hunk => GitDiffLineKind.hunk,
      rust.GitDiffLineKind.header => GitDiffLineKind.header,
      rust.GitDiffLineKind.context => GitDiffLineKind.context,
    };
  }

  GitHistoryRefCategory _toHistoryRefCategory(
    rust.GitHistoryRefCategory category,
  ) {
    return switch (category) {
      rust.GitHistoryRefCategory.branches => GitHistoryRefCategory.branches,
      rust.GitHistoryRefCategory.remoteBranches =>
        GitHistoryRefCategory.remoteBranches,
      rust.GitHistoryRefCategory.tags => GitHistoryRefCategory.tags,
      rust.GitHistoryRefCategory.commits => GitHistoryRefCategory.commits,
    };
  }

  GitCommitCompareStatus _toCommitCompareStatus(
    rust.GitCommitCompareStatus status,
  ) {
    return switch (status) {
      rust.GitCommitCompareStatus.ready => GitCommitCompareStatus.ready,
      rust.GitCommitCompareStatus.invalidCommit =>
        GitCommitCompareStatus.invalidCommit,
      rust.GitCommitCompareStatus.error => GitCommitCompareStatus.error,
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

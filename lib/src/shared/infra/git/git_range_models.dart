part of 'git_diff_models.dart';

/// One commit on the range from merge-base(base, HEAD) to HEAD.
class GitRangeCommit {
  const GitRangeCommit({
    required this.oid,
    required this.subject,
    required this.message,
  });

  final String oid;
  final String subject;
  final String message;
}

/// One file changed between merge-base(base, HEAD) and HEAD.
class GitRangeFile {
  const GitRangeFile({
    required this.path,
    required this.status,
    this.added,
    this.removed,
  });

  final String path;
  final GitChangeStatus status;
  final int? added;
  final int? removed;
}

/// Tree-to-tree range summary for AI prompts and hosted pull-request diffs.
class GitRangeContext {
  const GitRangeContext({
    required this.baseRef,
    required this.commits,
    required this.files,
    required this.patch,
    this.headOid,
    this.headBranch,
    this.mergeBase,
  });

  final String baseRef;
  final String? headOid;
  final String? headBranch;
  final String? mergeBase;
  final List<GitRangeCommit> commits;
  final List<GitRangeFile> files;
  final String patch;

  bool get isEmpty => commits.isEmpty && files.isEmpty && patch.trim().isEmpty;
}

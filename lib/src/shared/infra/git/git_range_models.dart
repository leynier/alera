part of 'git_diff_models.dart';

class const GitHostedReviewRange({
  required final String baseOid,
  required final String headOid,
  required final String retentionId,
});

/// One commit on the range from merge-base(base, HEAD) to HEAD.
class const GitRangeCommit({
  required final String oid,
  required final String subject,
  required final String message,
});

/// One file changed between merge-base(base, HEAD) and HEAD.
class const GitRangeFile({
  required final String path,
  required final GitChangeStatus status,
  final int? added,
  final int? removed,
});

/// Tree-to-tree range summary for AI prompts and hosted pull-request diffs.
class const GitRangeContext({
  required final String baseRef,
  required final List<GitRangeCommit> commits,
  required final List<GitRangeFile> files,
  required final String patch,
  final String? headOid,
  final String? headBranch,
  final String? mergeBase,
}) {
  bool get isEmpty => commits.isEmpty && files.isEmpty && patch.trim().isEmpty;
}

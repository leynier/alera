part of 'git_diff_models.dart';

enum GitHistoryRefCategory { branches, remoteBranches, tags, commits }

enum GitCommitCompareStatus { ready, invalidCommit, error }

class const GitHistoryItemRef({
  required final String id,
  required final String name,
  final String? revision,
  final GitHistoryRefCategory? category,
  final GitHistoryGraphColorId? color,
}) {
  GitHistoryItemRef copyWith({GitHistoryGraphColorId? color}) {
    return GitHistoryItemRef(
      id: id,
      name: name,
      revision: revision,
      category: category,
      color: color ?? this.color,
    );
  }
}

class const GitHistoryItem({
  required final String id,
  required final List<String> parentIds,
  required final String subject,
  required final String message,
  final String? displayId,
  final String? author,
  final String? authorEmail,
  final DateTime? timestamp,
  final List<GitHistoryItemRef> references = const <GitHistoryItemRef>[],
}) {
  GitHistoryItem copyWith({List<GitHistoryItemRef>? references}) {
    return GitHistoryItem(
      id: id,
      parentIds: parentIds,
      subject: subject,
      message: message,
      displayId: displayId,
      author: author,
      authorEmail: authorEmail,
      timestamp: timestamp,
      references: references ?? this.references,
    );
  }
}

class const GitHistoryResult({
  required final List<GitHistoryItem> items,
  required final bool hasIncomingChanges,
  required final bool hasOutgoingChanges,
  required final bool hasMore,
  required final int limit,
  final GitHistoryItemRef? currentRef,
  final GitHistoryItemRef? remoteRef,
  final GitHistoryItemRef? baseRef,
  final String? mergeBase,
});

class const GitCommitChangeEntry({
  required final String path,
  required final GitChangeStatus status,
  final String? oldPath,
  final int? added,
  final int? removed,
});

class const GitCommitCompareSummary({
  required final String commitOid,
  required final String? parentOid,
  required final String compareRef,
  required final String baseRef,
  required final int changedFiles,
  required final GitCommitCompareStatus status,
  final String? errorMessage,
});

class const GitCommitCompareResult({
  required final GitCommitCompareSummary summary,
  required final List<GitCommitChangeEntry> entries,
});

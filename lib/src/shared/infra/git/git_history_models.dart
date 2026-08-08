part of 'git_diff_models.dart';

enum GitHistoryRefCategory { branches, remoteBranches, tags, commits }

enum GitCommitCompareStatus { ready, invalidCommit, error }

class GitHistoryItemRef {
  const GitHistoryItemRef({
    required this.id,
    required this.name,
    this.revision,
    this.category,
    this.color,
  });

  final String id;
  final String name;
  final String? revision;
  final GitHistoryRefCategory? category;
  final GitHistoryGraphColorId? color;

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

class GitHistoryItem {
  const GitHistoryItem({
    required this.id,
    required this.parentIds,
    required this.subject,
    required this.message,
    this.displayId,
    this.author,
    this.authorEmail,
    this.timestamp,
    this.references = const <GitHistoryItemRef>[],
  });

  final String id;
  final List<String> parentIds;
  final String subject;
  final String message;
  final String? displayId;
  final String? author;
  final String? authorEmail;
  final DateTime? timestamp;
  final List<GitHistoryItemRef> references;

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

class GitHistoryResult {
  const GitHistoryResult({
    required this.items,
    required this.hasIncomingChanges,
    required this.hasOutgoingChanges,
    required this.hasMore,
    required this.limit,
    this.currentRef,
    this.remoteRef,
    this.baseRef,
    this.mergeBase,
  });

  final List<GitHistoryItem> items;
  final GitHistoryItemRef? currentRef;
  final GitHistoryItemRef? remoteRef;
  final GitHistoryItemRef? baseRef;
  final String? mergeBase;
  final bool hasIncomingChanges;
  final bool hasOutgoingChanges;
  final bool hasMore;
  final int limit;
}

class GitCommitChangeEntry {
  const GitCommitChangeEntry({
    required this.path,
    required this.status,
    this.oldPath,
    this.added,
    this.removed,
  });

  final String path;
  final String? oldPath;
  final GitChangeStatus status;
  final int? added;
  final int? removed;
}

class GitCommitCompareSummary {
  const GitCommitCompareSummary({
    required this.commitOid,
    required this.parentOid,
    required this.compareRef,
    required this.baseRef,
    required this.changedFiles,
    required this.status,
    this.errorMessage,
  });

  final String commitOid;
  final String? parentOid;
  final String compareRef;
  final String baseRef;
  final int changedFiles;
  final GitCommitCompareStatus status;
  final String? errorMessage;
}

class GitCommitCompareResult {
  const GitCommitCompareResult({required this.summary, required this.entries});

  final GitCommitCompareSummary summary;
  final List<GitCommitChangeEntry> entries;
}

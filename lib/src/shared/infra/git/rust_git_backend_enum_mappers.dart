part of 'rust_git_backend.dart';

extension on RustGitBackend {
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

  GitExplorerStatusSnapshot _toExplorerStatusSnapshot(
    explorer_rust.GitExplorerStatusSnapshot snapshot,
  ) {
    return GitExplorerStatusSnapshot(<String, GitExplorerStatus>{
      for (final entry in snapshot.entries)
        entry.path: switch (entry.status) {
          explorer_rust.GitExplorerStatus.untracked =>
            GitExplorerStatus.untracked,
          explorer_rust.GitExplorerStatus.added => GitExplorerStatus.added,
          explorer_rust.GitExplorerStatus.modified =>
            GitExplorerStatus.modified,
        },
    });
  }

  GitDiffLine _toDiffLine(rust.GitDiffLine line) {
    return GitDiffLine(text: line.text, kind: _toDiffLineKind(line.kind));
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

  GitDiffResult _toDiffResult(
    rust.GitDiffResult result, {
    String? sourceLabel,
  }) {
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
              isGitlink: file.isGitlink,
              truncated: file.truncated,
              linePreviewTruncated: file.linePreviewTruncated,
              sourceLabel: sourceLabel,
            ),
          )
          .toList(growable: false),
    );
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
      submodule: entry.submodule == null
          ? null
          : GitSubmoduleStatus(
              commitChanged: entry.submodule!.commitChanged,
              trackedChanges: entry.submodule!.trackedChanges,
              untrackedChanges: entry.submodule!.untrackedChanges,
              inspectable: entry.submodule!.inspectable,
            ),
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

  GitHistoryResult _toHistoryResult(rust.GitHistoryResult result) {
    return GitHistoryResult(
      items: result.items.map(_toHistoryItem).toList(growable: false),
      currentRef: result.currentRef == null
          ? null
          : _toHistoryItemRef(result.currentRef!),
      remoteRef: result.remoteRef == null
          ? null
          : _toHistoryItemRef(result.remoteRef!),
      baseRef: result.baseRef == null
          ? null
          : _toHistoryItemRef(result.baseRef!),
      mergeBase: result.mergeBase,
      hasIncomingChanges: result.hasIncomingChanges,
      hasOutgoingChanges: result.hasOutgoingChanges,
      hasMore: result.hasMore,
      limit: result.limit,
    );
  }

  GitHistoryItem _toHistoryItem(rust.GitHistoryItem item) {
    final timestamp = item.timestamp;
    return GitHistoryItem(
      id: item.id,
      parentIds: item.parentIds,
      subject: item.subject,
      message: item.message,
      displayId: item.displayId,
      author: item.author,
      authorEmail: item.authorEmail,
      timestamp: timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      references: item.references
          .map(_toHistoryItemRef)
          .toList(growable: false),
    );
  }

  GitHistoryItemRef _toHistoryItemRef(rust.GitHistoryItemRef itemRef) {
    return GitHistoryItemRef(
      id: itemRef.id,
      name: itemRef.name,
      revision: itemRef.revision,
      category: itemRef.category == null
          ? null
          : _toHistoryRefCategory(itemRef.category!),
    );
  }

  GitCommitCompareResult _toCommitCompareResult(
    rust.GitCommitCompareResult result,
  ) {
    return GitCommitCompareResult(
      summary: _toCommitCompareSummary(result.summary),
      entries: result.entries.map(_toCommitChangeEntry).toList(growable: false),
    );
  }

  GitCommitCompareSummary _toCommitCompareSummary(
    rust.GitCommitCompareSummary summary,
  ) {
    return GitCommitCompareSummary(
      commitOid: summary.commitOid,
      parentOid: summary.parentOid,
      compareRef: summary.compareRef,
      baseRef: summary.baseRef,
      changedFiles: summary.changedFiles,
      status: _toCommitCompareStatus(summary.status),
      errorMessage: summary.errorMessage,
    );
  }

  GitCommitChangeEntry _toCommitChangeEntry(rust.GitCommitChangeEntry entry) {
    return GitCommitChangeEntry(
      path: entry.path,
      oldPath: entry.oldPath,
      status: _toStatus(entry.status),
      added: entry.added,
      removed: entry.removed,
    );
  }
}

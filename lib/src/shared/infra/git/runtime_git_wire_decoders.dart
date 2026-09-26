part of 'runtime_git_backend.dart';

/// Decoders for the camelCase JSON the runtime's `git.*` verbs answer with.
/// The shape is `alera_core::source_control` serialized with serde, so field
/// names match the domain models one to one.

GitStatusResult _statusResult(Map<String, Object?> json) {
  return GitStatusResult(
    entries: _list(json['entries'], _changeEntry),
    groups: _list(json['groups'], _changeGroup),
  );
}

GitChangeEntry _changeEntry(Map<String, Object?> json) {
  final submodule = json['submodule'];
  return GitChangeEntry(
    path: _string(json['path']),
    oldPath: json['oldPath'] as String?,
    area: _area(json['area']),
    status: _changeStatus(json['status']),
    added: _optionalInt(json['added']),
    removed: _optionalInt(json['removed']),
    isBinary: json['isBinary'] == true,
    isLarge: json['isLarge'] == true,
    submodule: submodule is Map ? _submoduleStatus(_map(submodule)) : null,
  );
}

GitSubmoduleStatus _submoduleStatus(Map<String, Object?> json) {
  return GitSubmoduleStatus(
    commitChanged: json['commitChanged'] == true,
    trackedChanges: json['trackedChanges'] == true,
    untrackedChanges: json['untrackedChanges'] == true,
    inspectable: json['inspectable'] == true,
  );
}

GitChangeGroup _changeGroup(Map<String, Object?> json) {
  return GitChangeGroup(
    area: _area(json['area']),
    entries: _list(json['entries'], _changeEntry),
    treeRows: _list(json['treeRows'], _treeRow),
  );
}

GitChangeTreeRow _treeRow(Map<String, Object?> json) {
  final entry = json['entry'];
  return GitChangeTreeRow(
    kind: json['kind'] == 'directory'
        ? GitChangeTreeRowKind.directory
        : GitChangeTreeRowKind.file,
    name: _string(json['name']),
    path: _string(json['path']),
    depth: _int(json['depth']),
    fileCount: _int(json['fileCount']),
    entry: entry is Map ? _changeEntry(_map(entry)) : null,
  );
}

GitRepositoryState _repositoryState(Map<String, Object?> json) {
  return GitRepositoryState(
    branch: _string(json['branch']),
    upstream: json['upstream'] as String?,
    ahead: _int(json['ahead']),
    behind: _int(json['behind']),
    hasConflicts: json['hasConflicts'] == true,
    headMessage: json['headMessage'] as String?,
  );
}

GitStashEntry _stashEntry(Map<String, Object?> json) {
  return GitStashEntry(
    index: _int(json['index']),
    reference: _string(json['reference']),
    message: _string(json['message']),
    oid: _string(json['oid']),
  );
}

GitDiffResult _diffResult(Map<String, Object?> json) {
  return GitDiffResult(
    files: _list(json['files'], _diffFile),
    truncated: json['truncated'] == true,
  );
}

GitDiffFile _diffFile(Map<String, Object?> json) {
  return GitDiffFile(
    path: _string(json['path']),
    oldPath: json['oldPath'] as String?,
    area: _area(json['area']),
    status: _changeStatus(json['status']),
    lines: _list(json['lines'], _diffLine),
    added: _optionalInt(json['added']),
    removed: _optionalInt(json['removed']),
    isBinary: json['isBinary'] == true,
    isLarge: json['isLarge'] == true,
    isGitlink: json['isGitlink'] == true,
    truncated: json['truncated'] == true,
    linePreviewTruncated: json['linePreviewTruncated'] == true,
  );
}

GitDiffLine _diffLine(Map<String, Object?> json) {
  return GitDiffLine(
    text: _string(json['text']),
    kind: switch (json['kind']) {
      'addition' => GitDiffLineKind.addition,
      'deletion' => GitDiffLineKind.deletion,
      'hunk' => GitDiffLineKind.hunk,
      'header' => GitDiffLineKind.header,
      _ => GitDiffLineKind.context,
    },
  );
}

GitHistoryResult _historyResult(Map<String, Object?> json) {
  return GitHistoryResult(
    items: _list(json['items'], _historyItem),
    currentRef: _optionalRef(json['currentRef']),
    remoteRef: _optionalRef(json['remoteRef']),
    baseRef: _optionalRef(json['baseRef']),
    mergeBase: json['mergeBase'] as String?,
    hasIncomingChanges: json['hasIncomingChanges'] == true,
    hasOutgoingChanges: json['hasOutgoingChanges'] == true,
    hasMore: json['hasMore'] == true,
    limit: _int(json['limit']),
  );
}

GitHistoryItem _historyItem(Map<String, Object?> json) {
  final timestamp = json['timestamp'];
  return GitHistoryItem(
    id: _string(json['id']),
    parentIds: _stringList(json['parentIds']),
    subject: _string(json['subject']),
    message: _string(json['message']),
    displayId: json['displayId'] as String?,
    author: json['author'] as String?,
    authorEmail: json['authorEmail'] as String?,
    timestamp: timestamp is num
        ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt(), isUtc: true)
        : null,
    references: _list(json['references'], _historyRef),
  );
}

GitHistoryItemRef? _optionalRef(Object? value) =>
    value is Map ? _historyRef(_map(value)) : null;

GitHistoryItemRef _historyRef(Map<String, Object?> json) {
  return GitHistoryItemRef(
    id: _string(json['id']),
    name: _string(json['name']),
    revision: json['revision'] as String?,
    category: switch (json['category']) {
      'branches' => GitHistoryRefCategory.branches,
      'remoteBranches' => GitHistoryRefCategory.remoteBranches,
      'tags' => GitHistoryRefCategory.tags,
      'commits' => GitHistoryRefCategory.commits,
      _ => null,
    },
  );
}

GitCommitCompareResult _commitCompareResult(Map<String, Object?> json) {
  final summary = _map(json['summary']);
  return GitCommitCompareResult(
    summary: GitCommitCompareSummary(
      commitOid: _string(summary['commitOid']),
      parentOid: summary['parentOid'] as String?,
      compareRef: _string(summary['compareRef']),
      baseRef: _string(summary['baseRef']),
      changedFiles: _int(summary['changedFiles']),
      status: switch (summary['status']) {
        'ready' => GitCommitCompareStatus.ready,
        'invalidCommit' => GitCommitCompareStatus.invalidCommit,
        _ => GitCommitCompareStatus.error,
      },
      errorMessage: summary['errorMessage'] as String?,
    ),
    entries: _list(json['entries'], _commitChangeEntry),
  );
}

GitCommitChangeEntry _commitChangeEntry(Map<String, Object?> json) {
  return GitCommitChangeEntry(
    path: _string(json['path']),
    oldPath: json['oldPath'] as String?,
    status: _changeStatus(json['status']),
    added: _optionalInt(json['added']),
    removed: _optionalInt(json['removed']),
  );
}

GitRangeContext _rangeContext(Map<String, Object?> json) {
  return GitRangeContext(
    baseRef: _string(json['baseRef']),
    headOid: json['headOid'] as String?,
    headBranch: json['headBranch'] as String?,
    mergeBase: json['mergeBase'] as String?,
    commits: _list(
      json['commits'],
      (commit) => GitRangeCommit(
        oid: _string(commit['oid']),
        subject: _string(commit['subject']),
        message: _string(commit['message']),
      ),
    ),
    files: _list(
      json['files'],
      (file) => GitRangeFile(
        path: _string(file['path']),
        status: _changeStatus(file['status']),
        added: _optionalInt(file['added']),
        removed: _optionalInt(file['removed']),
      ),
    ),
    patch: _string(json['patch']),
  );
}

GitExplorerStatusSnapshot _explorerSnapshot(Map<String, Object?> json) {
  final statuses = <String, GitExplorerStatus>{};
  for (final entry in _list(json['entries'], (entry) => entry)) {
    final status = switch (entry['status']) {
      'untracked' => GitExplorerStatus.untracked,
      'added' => GitExplorerStatus.added,
      'modified' => GitExplorerStatus.modified,
      _ => null,
    };
    if (status != null) {
      statuses[_string(entry['path'])] = status;
    }
  }
  return GitExplorerStatusSnapshot(statuses);
}

GitChangeArea _area(Object? value) => switch (value) {
  'untracked' => GitChangeArea.untracked,
  'staged' => GitChangeArea.staged,
  _ => GitChangeArea.unstaged,
};

String _areaKey(GitChangeArea area) => area.key;

GitChangeStatus _changeStatus(Object? value) => switch (value) {
  'added' => GitChangeStatus.added,
  'deleted' => GitChangeStatus.deleted,
  'renamed' => GitChangeStatus.renamed,
  'copied' => GitChangeStatus.copied,
  'untracked' => GitChangeStatus.untracked,
  _ => GitChangeStatus.modified,
};

List<T> _list<T>(Object? value, T Function(Map<String, Object?>) decode) {
  if (value is! List) {
    return const [];
  }
  return <T>[
    for (final item in value)
      if (item is Map) decode(_map(item)),
  ];
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return <String>[
    for (final item in value)
      if (item is String) item,
  ];
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException('Runtime git payload must be a JSON object.');
}

String _string(Object? value) => value is String ? value : '';

int _int(Object? value) => value is num ? value.toInt() : 0;

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

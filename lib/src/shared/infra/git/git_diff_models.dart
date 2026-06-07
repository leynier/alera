enum GitChangeArea {
  untracked('untracked'),
  unstaged('unstaged'),
  staged('staged');

  const GitChangeArea(this.key);

  final String key;

  String get label => switch (this) {
    GitChangeArea.untracked => 'Untracked',
    GitChangeArea.unstaged => 'Unstaged',
    GitChangeArea.staged => 'Staged',
  };
}

enum GitChangeStatus { modified, added, deleted, renamed, copied, untracked }

enum GitChangeTreeRowKind { directory, file }

enum GitDiffLineKind { addition, deletion, hunk, header, context }

class GitStatusResult {
  const GitStatusResult({required this.entries, this.groups = const []});

  final List<GitChangeEntry> entries;
  final List<GitChangeGroup> groups;

  List<GitChangeGroup> get effectiveGroups {
    if (groups.isNotEmpty) {
      return groups;
    }
    return GitChangeGroup.fromEntries(entries);
  }

  List<GitChangeEntry> entriesForPath(String relativePath) {
    return entries
        .where((entry) => entry.path == relativePath)
        .toList(growable: false);
  }
}

class GitRepositoryState {
  const GitRepositoryState({
    required this.branch,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.hasConflicts = false,
    this.headMessage,
  });

  final String branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final bool hasConflicts;
  final String? headMessage;

  bool get hasUpstream => upstream != null && upstream!.isNotEmpty;
  bool get hasHeadCommit => headMessage != null;
}

class GitStashEntry {
  const GitStashEntry({
    required this.index,
    required this.reference,
    required this.message,
    required this.oid,
  });

  final int index;
  final String reference;
  final String message;
  final String oid;
}

class GitChangeGroup {
  const GitChangeGroup({
    required this.area,
    required this.entries,
    required this.treeRows,
  });

  final GitChangeArea area;
  final List<GitChangeEntry> entries;
  final List<GitChangeTreeRow> treeRows;

  static List<GitChangeGroup> fromEntries(List<GitChangeEntry> entries) {
    const orderedAreas = <GitChangeArea>[
      GitChangeArea.staged,
      GitChangeArea.unstaged,
      GitChangeArea.untracked,
    ];
    return <GitChangeGroup>[
      for (final area in orderedAreas)
        GitChangeGroup(
          area: area,
          entries:
              entries
                  .where((entry) => entry.area == area)
                  .toList(growable: false)
                ..sort((a, b) => a.path.compareTo(b.path)),
          treeRows: _treeRows(
            entries.where((entry) => entry.area == area).toList(growable: false)
              ..sort((a, b) => a.path.compareTo(b.path)),
          ),
        ),
    ].where((group) => group.entries.isNotEmpty).toList(growable: false);
  }

  static List<GitChangeTreeRow> _treeRows(List<GitChangeEntry> entries) {
    final root = _GitChangeTreeNode.directory(name: '', path: '', depth: 0);
    for (final entry in entries) {
      final parts = entry.path
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) {
        continue;
      }
      var parent = root;
      for (var index = 0; index < parts.length - 1; index += 1) {
        final path = parts.take(index + 1).join('/');
        parent = parent.directoryChild(parts[index], path, index);
      }
      parent.children.add(
        _GitChangeTreeNode.file(
          name: parts.last,
          path: entry.path,
          depth: parts.length - 1,
          entry: entry,
        ),
      );
    }
    root.sortRecursively();
    final rows = <GitChangeTreeRow>[];
    for (final child in root.children) {
      child.appendRows(rows);
    }
    return rows;
  }
}

class _GitChangeTreeNode {
  _GitChangeTreeNode._({
    required this.name,
    required this.path,
    required this.depth,
    this.entry,
  });

  factory _GitChangeTreeNode.directory({
    required String name,
    required String path,
    required int depth,
  }) => _GitChangeTreeNode._(name: name, path: path, depth: depth);

  factory _GitChangeTreeNode.file({
    required String name,
    required String path,
    required int depth,
    required GitChangeEntry entry,
  }) =>
      _GitChangeTreeNode._(name: name, path: path, depth: depth, entry: entry);

  final String name;
  final String path;
  final int depth;
  final GitChangeEntry? entry;
  final List<_GitChangeTreeNode> children = <_GitChangeTreeNode>[];

  _GitChangeTreeNode directoryChild(String name, String path, int depth) {
    for (final child in children) {
      if (child.entry == null && child.name == name) {
        return child;
      }
    }
    final child = _GitChangeTreeNode.directory(
      name: name,
      path: path,
      depth: depth,
    );
    children.add(child);
    return child;
  }

  void sortRecursively() {
    children.sort((a, b) {
      if (a.entry == null && b.entry != null) {
        return -1;
      }
      if (a.entry != null && b.entry == null) {
        return 1;
      }
      return a.name.compareTo(b.name);
    });
    for (final child in children) {
      child.sortRecursively();
    }
  }

  void appendRows(List<GitChangeTreeRow> rows) {
    rows.add(
      GitChangeTreeRow(
        kind: entry == null
            ? GitChangeTreeRowKind.directory
            : GitChangeTreeRowKind.file,
        name: name,
        path: path,
        depth: depth,
        fileCount: fileCount,
        entry: entry,
      ),
    );
    for (final child in children) {
      child.appendRows(rows);
    }
  }

  int get fileCount {
    if (entry != null) {
      return 1;
    }
    return children.fold<int>(0, (count, child) => count + child.fileCount);
  }
}

class GitChangeEntry {
  const GitChangeEntry({
    required this.path,
    required this.area,
    required this.status,
    this.oldPath,
    this.added,
    this.removed,
    this.isBinary = false,
    this.isLarge = false,
  });

  final String path;
  final String? oldPath;
  final GitChangeArea area;
  final GitChangeStatus status;
  final int? added;
  final int? removed;
  final bool isBinary;
  final bool isLarge;

  String get id => '${area.key}::$path';
}

class GitChangeTreeRow {
  const GitChangeTreeRow({
    required this.kind,
    required this.name,
    required this.path,
    required this.depth,
    required this.fileCount,
    this.entry,
  });

  final GitChangeTreeRowKind kind;
  final String name;
  final String path;
  final int depth;
  final int fileCount;
  final GitChangeEntry? entry;
}

class GitDiffResult {
  const GitDiffResult({required this.files, this.truncated = false});

  final List<GitDiffFile> files;
  final bool truncated;
}

class GitDiffFile {
  const GitDiffFile({
    required this.path,
    required this.area,
    required this.status,
    this.lines = const [],
    this.oldPath,
    this.added,
    this.removed,
    this.isBinary = false,
    this.isLarge = false,
    this.truncated = false,
    this.linePreviewTruncated = false,
  });

  final String path;
  final String? oldPath;
  final GitChangeArea area;
  final GitChangeStatus status;
  final List<GitDiffLine> lines;
  final int? added;
  final int? removed;
  final bool isBinary;
  final bool isLarge;
  final bool truncated;
  final bool linePreviewTruncated;
}

class GitDiffLine {
  const GitDiffLine({required this.text, required this.kind});

  const GitDiffLine.addition(String text)
    : this(text: text, kind: GitDiffLineKind.addition);

  const GitDiffLine.deletion(String text)
    : this(text: text, kind: GitDiffLineKind.deletion);

  const GitDiffLine.hunk(String text)
    : this(text: text, kind: GitDiffLineKind.hunk);

  const GitDiffLine.header(String text)
    : this(text: text, kind: GitDiffLineKind.header);

  const GitDiffLine.context(String text)
    : this(text: text, kind: GitDiffLineKind.context);

  final String text;
  final GitDiffLineKind kind;
}

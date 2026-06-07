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
  });

  final String branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final bool hasConflicts;

  bool get hasUpstream => upstream != null && upstream!.isNotEmpty;
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
    return <GitChangeGroup>[
      for (final area in GitChangeArea.values)
        GitChangeGroup(
          area: area,
          entries:
              entries
                  .where((entry) => entry.area == area)
                  .toList(growable: false)
                ..sort((a, b) => a.path.compareTo(b.path)),
          treeRows: _fallbackTreeRows(
            entries.where((entry) => entry.area == area).toList(growable: false)
              ..sort((a, b) => a.path.compareTo(b.path)),
          ),
        ),
    ].where((group) => group.entries.isNotEmpty).toList(growable: false);
  }

  static List<GitChangeTreeRow> _fallbackTreeRows(
    List<GitChangeEntry> entries,
  ) {
    return entries
        .map(
          (entry) => GitChangeTreeRow(
            kind: GitChangeTreeRowKind.file,
            name: entry.path.split('/').last,
            path: entry.path,
            depth: 0,
            fileCount: 1,
            entry: entry,
          ),
        )
        .toList(growable: false);
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

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

class GitStatusResult {
  const GitStatusResult({required this.entries});

  final List<GitChangeEntry> entries;

  List<GitChangeEntry> entriesForPath(String relativePath) {
    return entries
        .where((entry) => entry.path == relativePath)
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
    required this.patch,
    this.oldPath,
    this.added,
    this.removed,
    this.isBinary = false,
    this.isLarge = false,
    this.truncated = false,
  });

  final String path;
  final String? oldPath;
  final GitChangeArea area;
  final GitChangeStatus status;
  final String patch;
  final int? added;
  final int? removed;
  final bool isBinary;
  final bool isLarge;
  final bool truncated;
}

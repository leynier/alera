part 'git_range_models.dart';
part 'git_history_graph_models.dart';
part 'git_history_models.dart';

enum GitChangeArea(final String key) {
  untracked('untracked'),
  unstaged('unstaged'),
  staged('staged');

  String get label => switch (this) {
    GitChangeArea.untracked => 'Untracked',
    GitChangeArea.unstaged => 'Unstaged',
    GitChangeArea.staged => 'Staged',
  };
}

enum GitChangeStatus(final String badge) {
  modified('M'),
  added('A'),
  deleted('D'),
  renamed('R'),
  copied('C'),
  untracked('U'),
}

enum GitChangeTreeRowKind { directory, file }

enum GitDiffLineKind { addition, deletion, hunk, header, context }

class const GitStatusResult({
  required final List<GitChangeEntry> entries,
  final List<GitChangeGroup> groups = const [],
}) {
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

class const GitRepositoryState({
  required final String branch,
  final String? upstream,
  final int ahead = 0,
  final int behind = 0,
  final bool hasConflicts = false,
  final String? headMessage,
}) {
  bool get hasUpstream => upstream != null && upstream!.isNotEmpty;
  bool get hasHeadCommit => headMessage != null;
}

class const GitStashEntry({
  required final int index,
  required final String reference,
  required final String message,
  required final String oid,
});

class const GitChangeGroup({
  required final GitChangeArea area,
  required final List<GitChangeEntry> entries,
  required final List<GitChangeTreeRow> treeRows,
  this.unified = false,
}) {
  /// When true, the group holds files from every area in one list. [area] is
  /// only used as a collapse-key / bulk-action sentinel for the section.
  final bool unified;

  String get label => unified ? 'Changes' : area.label;

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

  /// Single Changes section with every entry sorted by path, then area so a
  /// staged and unstaged copy of the same file stay adjacent (staged first).
  static List<GitChangeGroup> unifiedFromEntries(List<GitChangeEntry> entries) {
    if (entries.isEmpty) {
      return const <GitChangeGroup>[];
    }
    final sorted = List<GitChangeEntry>.of(entries)
      ..sort((a, b) {
        final byPath = a.path.compareTo(b.path);
        if (byPath != 0) {
          return byPath;
        }
        return _areaSortIndex(a.area).compareTo(_areaSortIndex(b.area));
      });
    return <GitChangeGroup>[
      GitChangeGroup(
        area: .unstaged,
        entries: sorted,
        treeRows: _treeRows(sorted),
        unified: true,
      ),
    ];
  }

  static int _areaSortIndex(GitChangeArea area) {
    return switch (area) {
      GitChangeArea.staged => 0,
      GitChangeArea.unstaged => 1,
      GitChangeArea.untracked => 2,
    };
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
        .file(
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

class _GitChangeTreeNode._({
  required final String name,
  required final String path,
  required final int depth,
  final GitChangeEntry? entry,
}) {
  factory directory({
    required String name,
    required String path,
    required int depth,
  }) => _GitChangeTreeNode._(name: name, path: path, depth: depth);

  factory file({
    required String name,
    required String path,
    required int depth,
    required GitChangeEntry entry,
  }) =>
      _GitChangeTreeNode._(name: name, path: path, depth: depth, entry: entry);

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

class const GitChangeEntry({
  required final String path,
  required final GitChangeArea area,
  required final GitChangeStatus status,
  final String? oldPath,
  final int? added,
  final int? removed,
  final bool isBinary = false,
  final bool isLarge = false,
  final GitSubmoduleStatus? submodule,
  final String? submoduleRoot,
}) {
  String get id => '${area.key}::$path';

  bool get isSubmoduleChild => submoduleRoot != null;

  bool get isExpandableSubmodule =>
      submodule != null &&
      !isSubmoduleChild &&
      (submodule!.commitChanged ||
          submodule!.trackedChanges ||
          submodule!.untrackedChanges) &&
      submodule!.inspectable;

  bool get isSubmoduleWorktreeOnly =>
      area == GitChangeArea.unstaged &&
      submodule != null &&
      !submodule!.commitChanged;

  bool get canStageFromParent =>
      !isSubmoduleChild &&
      area != GitChangeArea.staged &&
      !isSubmoduleWorktreeOnly;

  bool get canUnstageFromParent =>
      !isSubmoduleChild && area == GitChangeArea.staged;

  bool get canDiscardFromParent =>
      !isSubmoduleChild &&
      area != GitChangeArea.staged &&
      !isSubmoduleWorktreeOnly &&
      (submodule == null ||
          (submodule!.inspectable &&
              !submodule!.trackedChanges &&
              !submodule!.untrackedChanges));

  GitChangeEntry insideSubmodule(String root) {
    final prefixedOldPath = oldPath == null ? null : '$root/$oldPath';
    return GitChangeEntry(
      path: '$root/$path',
      oldPath: prefixedOldPath,
      area: area,
      status: status,
      added: added,
      removed: removed,
      isBinary: isBinary,
      isLarge: isLarge,
      submodule: submodule,
      submoduleRoot: root,
    );
  }
}

class const GitSubmoduleStatus({
  required final bool commitChanged,
  required final bool trackedChanges,
  required final bool untrackedChanges,
  required final bool inspectable,
});

class const GitChangeTreeRow({
  required final GitChangeTreeRowKind kind,
  required final String name,
  required final String path,
  required final int depth,
  required final int fileCount,
  final GitChangeEntry? entry,
});

class const GitDiffResult({
  required final List<GitDiffFile> files,
  final bool truncated = false,
});

class const GitDiffFile({
  required final String path,
  required final GitChangeArea area,
  required final GitChangeStatus status,
  final List<GitDiffLine> lines = const [],
  final String? oldPath,
  final int? added,
  final int? removed,
  final bool isBinary = false,
  final bool isLarge = false,
  final bool isGitlink = false,
  final bool truncated = false,
  final bool linePreviewTruncated = false,
  final String? sourceLabel,
});

class const GitDiffLine({
  required final String text,
  required final GitDiffLineKind kind,
}) {
  const new addition(String text) : this(text: text, kind: .addition);

  const new deletion(String text) : this(text: text, kind: .deletion);

  const new hunk(String text) : this(text: text, kind: .hunk);

  const new header(String text) : this(text: text, kind: .header);

  const new context(String text) : this(text: text, kind: .context);
}

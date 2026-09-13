import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

/// One Source Control section: an area (Staged, Unstaged, Untracked) or the
/// single Changes list. Keys match the desktop panel so both collapse alike.
class const SourceControlSection({
  required final String key,
  required final String label,
  required final String treeScope,
  required final List<MobileGitChange> entries,
});

sealed class const SourceControlRow();

class const SourceControlSectionRow(final SourceControlSection section)
    extends SourceControlRow;

class const SourceControlDirectoryRow({
  required final String name,
  required final String nodeKey,
  required final int depth,
  required final int fileCount,
}) extends SourceControlRow;

class const SourceControlFileRow(
  final MobileGitChange change, {
  required final int depth,
  required final bool showParent,
}) extends SourceControlRow;

const List<(String, String)> _areas = <(String, String)>[
  ('staged', 'Staged'),
  ('unstaged', 'Unstaged'),
  ('untracked', 'Untracked'),
];

/// Case-insensitive match on the path and, for renames, the old path.
List<MobileGitChange> filterSourceControlChanges(
  List<MobileGitChange> entries,
  String filter,
) {
  final needle = filter.trim().toLowerCase();
  if (needle.isEmpty) {
    return entries;
  }
  return entries
      .where(
        (entry) =>
            entry.path.toLowerCase().contains(needle) ||
            (entry.oldPath?.toLowerCase().contains(needle) ?? false),
      )
      .toList(growable: false);
}

List<SourceControlSection> sourceControlSections(
  List<MobileGitChange> entries,
  MobileGitDiffGroupMode groupMode,
) {
  if (groupMode == MobileGitDiffGroupMode.unified) {
    if (entries.isEmpty) {
      return const <SourceControlSection>[];
    }
    final sorted = entries.toList()
      ..sort((a, b) {
        final byPath = a.path.compareTo(b.path);
        return byPath != 0 ? byPath : _areaRank(a.area) - _areaRank(b.area);
      });
    return <SourceControlSection>[
      SourceControlSection(
        key: 'section:unified',
        label: 'Changes',
        treeScope: 'unified',
        entries: sorted,
      ),
    ];
  }
  return <SourceControlSection>[
    for (final (area, label) in _areas)
      if (entries.where((entry) => entry.area == area).toList() case final items
          when items.isNotEmpty)
        SourceControlSection(
          key: 'section:$area',
          label: label,
          treeScope: area,
          entries: items,
        ),
  ];
}

int _areaRank(String area) =>
    _areas.indexWhere((candidate) => candidate.$1 == area);

List<SourceControlRow> sourceControlRows(
  List<SourceControlSection> sections, {
  required MobileGitDiffViewMode viewMode,
  required Set<String> collapsedKeys,
}) {
  final rows = <SourceControlRow>[];
  for (final section in sections) {
    rows.add(SourceControlSectionRow(section));
    if (collapsedKeys.contains(section.key)) {
      continue;
    }
    if (viewMode == MobileGitDiffViewMode.flat) {
      for (final change in section.entries) {
        rows.add(SourceControlFileRow(change, depth: 0, showParent: true));
      }
      continue;
    }
    _appendNode(_treeFor(section.entries), section, rows, collapsedKeys);
  }
  return rows;
}

/// Section keys plus every folder key, which is what Collapse All toggles.
Set<String> sourceControlCollapsibleKeys(
  List<SourceControlSection> sections, {
  required MobileGitDiffViewMode viewMode,
}) {
  final keys = <String>{};
  for (final section in sections) {
    keys.add(section.key);
    if (viewMode == MobileGitDiffViewMode.tree) {
      for (final change in section.entries) {
        final parts = _segments(change.path);
        for (var index = 1; index < parts.length; index += 1) {
          keys.add(_folderKey(section, parts.take(index).join('/')));
        }
      }
    }
  }
  return keys;
}

String _folderKey(SourceControlSection section, String path) =>
    'folder:${section.treeScope}:$path';

_Node _treeFor(List<MobileGitChange> entries) {
  final root = _Node('', '', -1);
  for (final change in entries) {
    final parts = _segments(change.path);
    if (parts.isEmpty) {
      continue;
    }
    var parent = root;
    for (var index = 0; index < parts.length - 1; index += 1) {
      final path = parts.take(index + 1).join('/');
      parent = parent.directories.putIfAbsent(
        parts[index],
        () => _Node(parts[index], path, index),
      );
    }
    parent.files.add(change);
  }
  return root;
}

void _appendNode(
  _Node node,
  SourceControlSection section,
  List<SourceControlRow> rows,
  Set<String> collapsedKeys,
) {
  final directories = node.directories.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final directory in directories) {
    final key = _folderKey(section, directory.path);
    rows.add(
      SourceControlDirectoryRow(
        name: directory.name,
        nodeKey: key,
        depth: directory.depth,
        fileCount: directory.fileCount,
      ),
    );
    if (collapsedKeys.contains(key)) {
      continue;
    }
    _appendNode(directory, section, rows, collapsedKeys);
  }
  final files = node.files.toList()
    ..sort((a, b) => _segments(a.path).last.compareTo(_segments(b.path).last));
  for (final change in files) {
    rows.add(
      SourceControlFileRow(change, depth: node.depth + 1, showParent: false),
    );
  }
}

List<String> _segments(String path) => path
    .replaceAll('\\', '/')
    .split('/')
    .where((part) => part.isNotEmpty)
    .toList(growable: false);

class _Node(final String name, final String path, final int depth) {
  final Map<String, _Node> directories = <String, _Node>{};
  final List<MobileGitChange> files = <MobileGitChange>[];

  int get fileCount => directories.values.fold(
    files.length,
    (total, directory) => total + directory.fileCount,
  );
}

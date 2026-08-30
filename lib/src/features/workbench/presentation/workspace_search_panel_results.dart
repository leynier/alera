part of 'workspace_search_panel.dart';

final p.Context _searchPathContext = p.Context(style: p.Style.posix);

sealed class const _SearchRow();

class const _SearchFileRow(
  final native.WorkspaceSearchFileResult file, {
  required final int depth,
}) extends _SearchRow;

class const _SearchMatchRow(
  final native.WorkspaceSearchFileResult file,
  final native.WorkspaceSearchMatch match, {
  required final int depth,
}) extends _SearchRow;

class const _SearchDirectoryRow({
  required final String name,
  required final String path,
  required final int depth,
  required final int matchCount,
}) extends _SearchRow;

class const _SearchRows(final List<_SearchRow> items) {
  factory from(
    native.WorkspaceSearchResult? result, {
    required Set<String> collapsedResultNodeKeys,
    required bool viewAsTree,
  }) {
    if (result == null) {
      return const _SearchRows(<_SearchRow>[]);
    }
    if (viewAsTree) {
      return _SearchRows(_treeRowsFrom(result, collapsedResultNodeKeys));
    }
    final rows = <_SearchRow>[];
    for (final file in result.files) {
      rows.add(_SearchFileRow(file, depth: 0));
      if (collapsedResultNodeKeys.contains(
        workspaceSearchFileNodeKey(file.relativePath),
      )) {
        continue;
      }
      for (final match in file.matches) {
        rows.add(_SearchMatchRow(file, match, depth: 0));
      }
    }
    return _SearchRows(rows);
  }
}

List<_SearchRow> _treeRowsFrom(
  native.WorkspaceSearchResult result,
  Set<String> collapsedResultNodeKeys,
) {
  final root = _SearchTreeDirectory('', '');
  for (final file in result.files) {
    final segments = _pathSegments(file.relativePath);
    if (segments.length <= 1) {
      root.files.add(file);
      continue;
    }
    var directory = root;
    for (var index = 0; index < segments.length - 1; index += 1) {
      final name = segments[index];
      final path = directory.path.isEmpty
          ? name
          : _searchPathContext.join(directory.path, name);
      directory = directory.directories.putIfAbsent(
        name,
        () => _SearchTreeDirectory(name, path),
      );
      directory.matchCount += file.matches.length;
    }
    directory.files.add(file);
  }
  final rows = <_SearchRow>[];
  _appendTreeRows(root, rows, collapsedResultNodeKeys, -1);
  return rows;
}

void _appendTreeRows(
  _SearchTreeDirectory directory,
  List<_SearchRow> rows,
  Set<String> collapsedResultNodeKeys,
  int depth,
) {
  final children = directory.directories.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final child in children) {
    rows.add(
      _SearchDirectoryRow(
        name: child.name,
        path: child.path,
        depth: depth + 1,
        matchCount: child.matchCount,
      ),
    );
    if (collapsedResultNodeKeys.contains(
      workspaceSearchDirectoryNodeKey(child.path),
    )) {
      continue;
    }
    _appendTreeRows(child, rows, collapsedResultNodeKeys, depth + 1);
  }
  final files = directory.files.toList(growable: false)
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  for (final file in files) {
    rows.add(_SearchFileRow(file, depth: depth + 1));
    if (collapsedResultNodeKeys.contains(
      workspaceSearchFileNodeKey(file.relativePath),
    )) {
      continue;
    }
    for (final match in file.matches) {
      rows.add(_SearchMatchRow(file, match, depth: depth + 2));
    }
  }
}

List<String> _pathSegments(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  return _searchPathContext
      .split(normalized)
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}

class _SearchTreeDirectory(final String name, final String path) {
  int matchCount = 0;
  final Map<String, _SearchTreeDirectory> directories =
      <String, _SearchTreeDirectory>{};
  final List<native.WorkspaceSearchFileResult> files =
      <native.WorkspaceSearchFileResult>[];
}

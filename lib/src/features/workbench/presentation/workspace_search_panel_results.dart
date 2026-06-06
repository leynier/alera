part of 'workspace_search_panel.dart';

sealed class _SearchRow {
  const _SearchRow();
}

class _SearchFileRow extends _SearchRow {
  const _SearchFileRow(this.file);

  final native.WorkspaceSearchFileResult file;
}

class _SearchMatchRow extends _SearchRow {
  const _SearchMatchRow(this.file, this.match);

  final native.WorkspaceSearchFileResult file;
  final native.WorkspaceSearchMatch match;
}

class _SearchRows {
  const _SearchRows(this.items);

  final List<_SearchRow> items;

  factory _SearchRows.from(
    native.WorkspaceSearchResult? result, {
    required Set<String> collapsedFilePaths,
  }) {
    if (result == null) {
      return const _SearchRows(<_SearchRow>[]);
    }
    final rows = <_SearchRow>[];
    for (final file in result.files) {
      rows.add(_SearchFileRow(file));
      if (collapsedFilePaths.contains(file.relativePath)) {
        continue;
      }
      for (final match in file.matches) {
        rows.add(_SearchMatchRow(file, match));
      }
    }
    return _SearchRows(rows);
  }
}

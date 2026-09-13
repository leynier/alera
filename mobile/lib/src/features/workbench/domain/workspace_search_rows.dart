import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

/// Flattened Search results, so a long result list stays one lazy
/// `ListView.builder` and collapsing a node is just skipping its rows. Node
/// keys match the desktop panel (`dir:<path>` / `file:<path>`).
sealed class const WorkspaceSearchRow();

class const WorkspaceSearchDirectoryRow({
  required final String name,
  required final String path,
  required final int depth,
  required final int matchCount,
}) extends WorkspaceSearchRow;

class const WorkspaceSearchFileRow(
  final MobileWorkspaceSearchFile file, {
  required final int depth,
}) extends WorkspaceSearchRow;

class const WorkspaceSearchMatchRow(
  final MobileWorkspaceSearchFile file,
  final MobileWorkspaceSearchMatch match, {
  required final int depth,
}) extends WorkspaceSearchRow;

String workspaceSearchDirectoryNodeKey(String path) => 'dir:$path';

String workspaceSearchFileNodeKey(String relativePath) => 'file:$relativePath';

List<WorkspaceSearchRow> workspaceSearchRows(
  MobileWorkspaceSearchResult? result, {
  required Set<String> collapsedNodeKeys,
  required bool viewAsTree,
}) {
  if (result == null) {
    return const <WorkspaceSearchRow>[];
  }
  final rows = <WorkspaceSearchRow>[];
  if (!viewAsTree) {
    for (final file in result.files) {
      _appendFile(rows, file, 0, collapsedNodeKeys);
    }
    return rows;
  }
  final root = _Directory('', '');
  for (final file in result.files) {
    final segments = _segments(file.relativePath);
    var directory = root;
    for (var index = 0; index < segments.length - 1; index += 1) {
      final name = segments[index];
      final path = directory.path.isEmpty ? name : '${directory.path}/$name';
      directory = directory.directories.putIfAbsent(
        name,
        () => _Directory(name, path),
      );
      directory.matchCount += file.matches.length;
    }
    directory.files.add(file);
  }
  _appendDirectory(root, rows, collapsedNodeKeys, -1);
  return rows;
}

/// Every key Collapse All would collapse for the current view.
Set<String> workspaceSearchCollapsibleNodeKeys(
  MobileWorkspaceSearchResult? result, {
  required bool viewAsTree,
}) {
  if (result == null) {
    return const <String>{};
  }
  final keys = <String>{};
  for (final file in result.files) {
    if (viewAsTree) {
      final segments = _segments(file.relativePath);
      for (var index = 1; index < segments.length; index += 1) {
        keys.add(
          workspaceSearchDirectoryNodeKey(segments.take(index).join('/')),
        );
      }
    }
    keys.add(workspaceSearchFileNodeKey(file.relativePath));
  }
  return keys;
}

void _appendDirectory(
  _Directory directory,
  List<WorkspaceSearchRow> rows,
  Set<String> collapsedNodeKeys,
  int depth,
) {
  final children = directory.directories.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final child in children) {
    rows.add(
      WorkspaceSearchDirectoryRow(
        name: child.name,
        path: child.path,
        depth: depth + 1,
        matchCount: child.matchCount,
      ),
    );
    if (!collapsedNodeKeys.contains(
      workspaceSearchDirectoryNodeKey(child.path),
    )) {
      _appendDirectory(child, rows, collapsedNodeKeys, depth + 1);
    }
  }
  final files = directory.files.toList(growable: false)
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  for (final file in files) {
    _appendFile(rows, file, depth + 1, collapsedNodeKeys);
  }
}

void _appendFile(
  List<WorkspaceSearchRow> rows,
  MobileWorkspaceSearchFile file,
  int depth,
  Set<String> collapsedNodeKeys,
) {
  rows.add(WorkspaceSearchFileRow(file, depth: depth));
  if (collapsedNodeKeys.contains(
    workspaceSearchFileNodeKey(file.relativePath),
  )) {
    return;
  }
  for (final match in file.matches) {
    rows.add(WorkspaceSearchMatchRow(file, match, depth: depth + 1));
  }
}

List<String> _segments(String relativePath) => relativePath
    .replaceAll('\\', '/')
    .split('/')
    .where((segment) => segment.isNotEmpty)
    .toList(growable: false);

class _Directory(final String name, final String path) {
  int matchCount = 0;
  final Map<String, _Directory> directories = <String, _Directory>{};
  final List<MobileWorkspaceSearchFile> files = <MobileWorkspaceSearchFile>[];
}

/// A `[start, end)` range of UTF-16 offsets in a preview line.
class const WorkspaceSearchTextRange({
  required final int start,
  required final int end,
});

/// The host reports columns in characters (Unicode scalar values) while Dart
/// strings index UTF-16 code units, so an emoji before a match would shift the
/// highlight without this conversion.
WorkspaceSearchTextRange workspaceSearchMatchRange(
  MobileWorkspaceSearchMatch match,
  String text,
) {
  final startColumn = (match.displayColumn ?? match.column) - 1;
  final length = match.displayMatchLength ?? match.matchLength;
  final start = _utf16Offset(text, startColumn);
  final end = _utf16Offset(text, startColumn + length);
  return WorkspaceSearchTextRange(
    start: start.clamp(0, text.length),
    end: end.clamp(start.clamp(0, text.length), text.length),
  );
}

int _utf16Offset(String text, int charOffset) {
  var remaining = charOffset < 0 ? 0 : charOffset;
  var offset = 0;
  while (offset < text.length && remaining > 0) {
    final unit = text.codeUnitAt(offset);
    final pair =
        unit >= 0xD800 &&
        unit <= 0xDBFF &&
        offset + 1 < text.length &&
        text.codeUnitAt(offset + 1) >= 0xDC00 &&
        text.codeUnitAt(offset + 1) <= 0xDFFF;
    offset += pair ? 2 : 1;
    remaining -= 1;
  }
  return offset;
}

/// Same wording as the desktop panel, so both surfaces report a partial
/// replace identically.
String? workspaceSearchReplaceConflictMessage(
  MobileWorkspaceReplaceResult result,
) {
  if (result.conflicts.isEmpty) {
    return null;
  }
  final skipped = result.conflicts
      .map((conflict) => conflict.relativePath)
      .toSet()
      .length;
  final first = result.conflicts.first;
  final firstReason = '${first.relativePath}: ${first.reason}';
  final skippedFiles = skipped == 1 ? '1 file' : '$skipped files';
  if (result.matchesReplaced > 0) {
    final matchWord = result.matchesReplaced == 1 ? 'match' : 'matches';
    return 'Replaced ${result.matchesReplaced} $matchWord. $skippedFiles skipped. $firstReason';
  }
  return 'Replace skipped $skippedFiles. $firstReason';
}

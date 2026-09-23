/// A local draft comment destined for an agent, not a hosted review thread.
enum WorkspaceAgentCommentKind { file, diff }

/// Which side of a diff a line number refers to.
///
/// File comments and added/context diff lines use [newSide] (working tree).
/// Deletion-only anchors exist only on [oldSide] and must not be labeled as a
/// bare `line N`, or an agent will treat them as working-tree numbers.
enum WorkspaceAgentCommentLineSide { newSide, oldSide }

class const WorkspaceAgentCommentLineRange({
  required final int startLine,
  required final int endLine,
  final WorkspaceAgentCommentLineSide side =
      WorkspaceAgentCommentLineSide.newSide,
}) {
  bool get isSingleLine => startLine == endLine;

  bool get isOldSide => side == WorkspaceAgentCommentLineSide.oldSide;

  String get label {
    if (isOldSide) {
      return isSingleLine
          ? 'old line $startLine'
          : 'old lines $startLine-$endLine';
    }
    return isSingleLine ? 'line $startLine' : 'lines $startLine-$endLine';
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceAgentCommentLineRange &&
        startLine == other.startLine &&
        endLine == other.endLine &&
        side == other.side;
  }

  @override
  int get hashCode => Object.hash(startLine, endLine, side);
}

class const WorkspaceAgentComment({
  required final String id,
  required final WorkspaceAgentCommentKind kind,
  required final String path,
  required final String body,
  final WorkspaceAgentCommentLineRange? lineRange,
  final String? hunkHeader,
  final String? areaLabel,
  final String? snippet,
});

String workspaceAgentCommentLocationLabel(WorkspaceAgentComment comment) {
  final parts = <String>[comment.path];
  final area = comment.areaLabel?.trim();
  if (area != null && area.isNotEmpty) {
    parts.add('($area)');
  }
  final hunk = comment.hunkHeader?.trim();
  if (hunk != null && hunk.isNotEmpty) {
    parts.add(hunk);
  }
  final range = comment.lineRange;
  if (range != null) {
    parts.add(range.label);
  }
  return parts.join(' · ');
}

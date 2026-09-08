/// A local draft comment destined for an agent, not a hosted review thread.
enum WorkspaceAgentCommentKind { file, diff }

class const WorkspaceAgentCommentLineRange({
  required final int startLine,
  required final int endLine,
}) {
  bool get isSingleLine => startLine == endLine;

  String get label {
    if (isSingleLine) {
      return 'line $startLine';
    }
    return 'lines $startLine-$endLine';
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceAgentCommentLineRange &&
        startLine == other.startLine &&
        endLine == other.endLine;
  }

  @override
  int get hashCode => Object.hash(startLine, endLine);
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

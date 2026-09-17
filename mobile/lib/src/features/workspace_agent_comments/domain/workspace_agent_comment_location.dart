import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';

final RegExp _hunkHeaderPattern = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
);

class const WorkspaceAgentDiffLineAnchor({
  required final int index,
  required final MobileGitDiffLine line,
  final String? hunkHeader,
  final int? oldLine,
  final int? newLine,
  final int? hunkNewStart,
  final int? hunkNewEnd,
});

class const _ParsedHunkHeader({
  required final String text,
  required final int oldStart,
  required final int oldCount,
  required final int newStart,
  required final int newCount,
});

List<WorkspaceAgentDiffLineAnchor> workspaceAgentDiffLineAnchors(
  List<MobileGitDiffLine> lines,
) {
  final anchors = <WorkspaceAgentDiffLineAnchor>[];
  String? hunkHeader;
  int? oldLine;
  int? newLine;
  int? hunkNewStart;
  int? hunkNewEnd;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    switch (line.kind) {
      case 'hunk':
        final parsed = _parseHunkHeader(line.text);
        hunkHeader = parsed?.text ?? line.text.trim();
        oldLine = parsed == null || parsed.oldCount == 0
            ? null
            : parsed.oldStart;
        newLine = parsed == null || parsed.newCount == 0
            ? null
            : parsed.newStart;
        hunkNewStart = parsed == null || parsed.newCount == 0
            ? null
            : parsed.newStart;
        hunkNewEnd = parsed == null || parsed.newCount == 0
            ? null
            : parsed.newStart + parsed.newCount - 1;
        anchors.add(
          WorkspaceAgentDiffLineAnchor(
            index: index,
            line: line,
            hunkHeader: hunkHeader,
            hunkNewStart: hunkNewStart,
            hunkNewEnd: hunkNewEnd,
          ),
        );
      case 'header':
        hunkHeader = null;
        oldLine = null;
        newLine = null;
        hunkNewStart = null;
        hunkNewEnd = null;
        anchors.add(WorkspaceAgentDiffLineAnchor(index: index, line: line));
      case 'addition':
        final thisNew = newLine;
        if (thisNew != null) {
          newLine = thisNew + 1;
        }
        anchors.add(
          WorkspaceAgentDiffLineAnchor(
            index: index,
            line: line,
            hunkHeader: hunkHeader,
            newLine: thisNew,
            hunkNewStart: hunkNewStart,
            hunkNewEnd: hunkNewEnd,
          ),
        );
      case 'deletion':
        final thisOld = oldLine;
        if (thisOld != null) {
          oldLine = thisOld + 1;
        }
        anchors.add(
          WorkspaceAgentDiffLineAnchor(
            index: index,
            line: line,
            hunkHeader: hunkHeader,
            oldLine: thisOld,
            hunkNewStart: hunkNewStart,
            hunkNewEnd: hunkNewEnd,
          ),
        );
      default:
        // Mobile git.diff labels "\ No newline at end of file" as context.
        // Counting it would shift the following code line.
        if (line.text.startsWith(r'\')) {
          anchors.add(
            WorkspaceAgentDiffLineAnchor(
              index: index,
              line: line,
              hunkHeader: hunkHeader,
              hunkNewStart: hunkNewStart,
              hunkNewEnd: hunkNewEnd,
            ),
          );
        } else {
          final thisOld = oldLine;
          final thisNew = newLine;
          if (thisOld != null) {
            oldLine = thisOld + 1;
          }
          if (thisNew != null) {
            newLine = thisNew + 1;
          }
          anchors.add(
            WorkspaceAgentDiffLineAnchor(
              index: index,
              line: line,
              hunkHeader: hunkHeader,
              oldLine: thisOld,
              newLine: thisNew,
              hunkNewStart: hunkNewStart,
              hunkNewEnd: hunkNewEnd,
            ),
          );
        }
    }
  }
  return anchors;
}

WorkspaceAgentCommentLineRange? workspaceAgentCommentRangeForDiffAnchor(
  WorkspaceAgentDiffLineAnchor anchor,
) {
  if (anchor.line.kind == 'hunk') {
    final start = anchor.hunkNewStart;
    final end = anchor.hunkNewEnd;
    if (start == null || end == null) {
      return null;
    }
    return WorkspaceAgentCommentLineRange(startLine: start, endLine: end);
  }
  final newLine = anchor.newLine;
  if (newLine != null) {
    return WorkspaceAgentCommentLineRange(startLine: newLine, endLine: newLine);
  }
  final oldLine = anchor.oldLine;
  if (oldLine != null) {
    return WorkspaceAgentCommentLineRange(
      startLine: oldLine,
      endLine: oldLine,
      side: WorkspaceAgentCommentLineSide.oldSide,
    );
  }
  return null;
}

String? workspaceAgentCommentSnippetForDiffAnchor({
  required List<MobileGitDiffLine> lines,
  required WorkspaceAgentDiffLineAnchor anchor,
}) {
  if (anchor.line.kind == 'hunk') {
    final body = <String>[anchor.line.text];
    for (var index = anchor.index + 1; index < lines.length; index += 1) {
      final line = lines[index];
      if (line.kind == 'hunk' || line.kind == 'header') {
        break;
      }
      body.add(line.text);
    }
    return capWorkspaceAgentCommentSnippet(body.join('\n'));
  }
  return capWorkspaceAgentCommentSnippet(anchor.line.text);
}

_ParsedHunkHeader? _parseHunkHeader(String text) {
  final match = _hunkHeaderPattern.firstMatch(text.trim());
  if (match == null) {
    return null;
  }
  final oldStart = int.parse(match.group(1)!);
  final oldCount = int.parse(match.group(2) ?? '1');
  final newStart = int.parse(match.group(3)!);
  final newCount = int.parse(match.group(4) ?? '1');
  return _ParsedHunkHeader(
    text: text.trim(),
    oldStart: oldStart,
    oldCount: oldCount,
    newStart: newStart,
    newCount: newCount,
  );
}

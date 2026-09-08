import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter/services.dart';

final RegExp _hunkHeaderPattern = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
);

class const WorkspaceAgentDiffLineAnchor({
  required final int index,
  required final GitDiffLine line,
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

WorkspaceAgentCommentLineRange? workspaceAgentCommentLineRangeForSelection({
  required String text,
  required TextSelection selection,
}) {
  if (text.isEmpty) {
    return null;
  }
  final maxOffset = text.length;
  final rawStart = selection.isValid ? selection.start : 0;
  final rawEnd = selection.isValid ? selection.end : rawStart;
  final from = rawStart.clamp(0, maxOffset);
  final to = rawEnd.clamp(0, maxOffset);
  final start = from <= to ? from : to;
  final end = from <= to ? to : from;
  final startLine = _lineNumberAt(text, start);
  final endLine = start == end
      ? startLine
      : _lineNumberAt(text, end > start ? end - 1 : end);
  return WorkspaceAgentCommentLineRange(
    startLine: startLine,
    endLine: endLine < startLine ? startLine : endLine,
  );
}

String? workspaceAgentCommentSnippetForSelection({
  required String text,
  required TextSelection selection,
}) {
  if (text.isEmpty) {
    return null;
  }
  if (!selection.isValid || selection.isCollapsed) {
    final offset = (selection.isValid ? selection.baseOffset : 0).clamp(
      0,
      text.length,
    );
    return capWorkspaceAgentCommentSnippet(_lineTextAt(text, offset));
  }
  final from = selection.start < selection.end
      ? selection.start
      : selection.end;
  final to = selection.start < selection.end ? selection.end : selection.start;
  final start = from.clamp(0, text.length);
  final end = to.clamp(0, text.length);
  if (start >= end) {
    return null;
  }
  return capWorkspaceAgentCommentSnippet(text.substring(start, end));
}

List<WorkspaceAgentDiffLineAnchor> workspaceAgentDiffLineAnchors(
  List<GitDiffLine> lines,
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
      case GitDiffLineKind.hunk:
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
      case GitDiffLineKind.header:
        hunkHeader = null;
        oldLine = null;
        newLine = null;
        hunkNewStart = null;
        hunkNewEnd = null;
        anchors.add(WorkspaceAgentDiffLineAnchor(index: index, line: line));
      case GitDiffLineKind.addition:
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
      case GitDiffLineKind.deletion:
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
      case GitDiffLineKind.context:
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
  return anchors;
}

WorkspaceAgentCommentLineRange? workspaceAgentCommentRangeForDiffAnchor(
  WorkspaceAgentDiffLineAnchor anchor,
) {
  if (anchor.line.kind == GitDiffLineKind.hunk) {
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
    return WorkspaceAgentCommentLineRange(startLine: oldLine, endLine: oldLine);
  }
  return null;
}

String? workspaceAgentCommentSnippetForDiffAnchor({
  required List<GitDiffLine> lines,
  required WorkspaceAgentDiffLineAnchor anchor,
}) {
  if (anchor.line.kind == GitDiffLineKind.hunk) {
    final body = <String>[anchor.line.text];
    for (var index = anchor.index + 1; index < lines.length; index += 1) {
      final line = lines[index];
      if (line.kind == GitDiffLineKind.hunk ||
          line.kind == GitDiffLineKind.header) {
        break;
      }
      body.add(line.text);
    }
    return capWorkspaceAgentCommentSnippet(body.join('\n'));
  }
  return capWorkspaceAgentCommentSnippet(anchor.line.text);
}

int _lineNumberAt(String text, int offset) {
  var line = 1;
  final limit = offset.clamp(0, text.length);
  for (var index = 0; index < limit; index += 1) {
    if (text.codeUnitAt(index) == 0x0A) {
      line += 1;
    }
  }
  return line;
}

String _lineTextAt(String text, int offset) {
  final clamped = offset.clamp(0, text.length);
  var start = 0;
  for (var index = clamped - 1; index >= 0; index -= 1) {
    if (text.codeUnitAt(index) == 0x0A) {
      start = index + 1;
      break;
    }
  }
  var end = text.length;
  for (var index = clamped; index < text.length; index += 1) {
    if (text.codeUnitAt(index) == 0x0A) {
      end = index;
      break;
    }
  }
  return text.substring(start, end);
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

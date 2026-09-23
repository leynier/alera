import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';

const int workspaceAgentCommentMaxSnippetChars = 2000;
const int workspaceAgentCommentMaxSnippetLines = 24;

String? capWorkspaceAgentCommentSnippet(String? snippet) {
  final raw = snippet?.replaceAll('\r\n', '\n').trimRight();
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  var text = raw;
  final lines = text.split('\n');
  if (lines.length > workspaceAgentCommentMaxSnippetLines) {
    text =
        '${lines.take(workspaceAgentCommentMaxSnippetLines).join('\n')}\n...';
  }
  if (text.length > workspaceAgentCommentMaxSnippetChars) {
    text = '${text.substring(0, workspaceAgentCommentMaxSnippetChars)}...';
  }
  return text;
}

String workspaceAgentCommentPrompt(List<WorkspaceAgentComment> comments) {
  final blocks = <String>[];
  for (var index = 0; index < comments.length; index += 1) {
    final comment = comments[index];
    final body = comment.body.trim();
    if (body.isEmpty) {
      continue;
    }
    blocks.add(_commentBlock(index + 1, comment, body));
  }
  if (blocks.isEmpty) {
    return '';
  }
  return 'Please act on these comments in the current workspace.\n\n'
      '${blocks.join('\n\n')}';
}

AgentTaskDispatchRequest? workspaceAgentCommentDispatchRequest({
  required String workspaceId,
  required List<WorkspaceAgentComment> comments,
}) {
  final prompt = workspaceAgentCommentPrompt(comments);
  if (prompt.isEmpty) {
    return null;
  }
  final count = comments
      .where((comment) => comment.body.trim().isNotEmpty)
      .length;
  return AgentTaskDispatchRequest(
    workspaceId: workspaceId,
    prompt: prompt,
    title: 'Send Comments to Agent',
    message: count <= 1
        ? 'Choose a running agent or open a new tab from a profile.'
        : 'These $count comments will be sent together. Choose a running agent or open a new tab from a profile.',
  );
}

String _commentBlock(int number, WorkspaceAgentComment comment, String body) {
  final header = StringBuffer('## $number. ')
    ..write(comment.kind == WorkspaceAgentCommentKind.diff ? 'Diff' : 'File')
    ..write(' `${comment.path}`');
  final area = comment.areaLabel?.trim();
  if (area != null && area.isNotEmpty) {
    header.write(' ($area)');
  }
  final hunk = comment.hunkHeader?.trim();
  if (hunk != null && hunk.isNotEmpty) {
    header.write(' hunk `$hunk`');
  }
  final range = comment.lineRange;
  if (range != null) {
    header.write(' ${range.label}');
  }
  final snippet = capWorkspaceAgentCommentSnippet(comment.snippet);
  final buffer = StringBuffer(header.toString());
  if (snippet != null) {
    buffer
      ..write('\n```\n')
      ..write(snippet)
      ..write('\n```');
  }
  buffer
    ..write('\nComment:\n')
    ..write(body);
  return buffer.toString();
}

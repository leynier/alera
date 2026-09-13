import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';

// Ported from the desktop `workspace_agent_comment_prompt.dart` so an agent
// receives the same prompt whichever surface the comments were written on.
// Keep the two in sync.
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

String _commentBlock(int number, WorkspaceAgentComment comment, String body) {
  final buffer = StringBuffer('## $number. File `${comment.path}`');
  final snippet = capWorkspaceAgentCommentSnippet(comment.snippet);
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

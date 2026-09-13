import 'package:alera/src/features/linked_issues/domain/issue_details.dart';

/// Longest branch slug derived from an issue title, before the number prefix.
const int _maxBranchSlugLength = 48;

/// Workspace name prefilled from an issue: its title.
String issueWorkspaceName(IssueDetails issue) => issue.title.trim();

/// Branch prefilled from an issue: `<number>-<slug of title>`, cut at a word
/// boundary so it stays readable in the sidebar.
String issueBranchName(IssueDetails issue) {
  final slug = _slug(issue.title);
  return slug.isEmpty ? '${issue.number}' : '${issue.number}-$slug';
}

/// Starting prompt prefilled from an issue: title, body and a link back.
String issuePrompt(IssueDetails issue) {
  final body = issue.body?.trim();
  return <String>[
    issue.title.trim(),
    if (body != null && body.isNotEmpty) body,
    issue.url,
  ].join('\n\n');
}

String _slug(String title) {
  final words = title
      .toLowerCase()
      .split(RegExp('[^a-z0-9]+'))
      .where((word) => word.isNotEmpty);
  final buffer = StringBuffer();
  for (final word in words) {
    final next = buffer.isEmpty ? word : '-$word';
    if (buffer.length + next.length > _maxBranchSlugLength) {
      if (buffer.isEmpty) {
        buffer.write(word.substring(0, _maxBranchSlugLength));
      }
      break;
    }
    buffer.write(next);
  }
  return buffer.toString();
}

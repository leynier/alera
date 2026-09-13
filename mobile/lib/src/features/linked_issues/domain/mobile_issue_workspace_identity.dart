import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';

/// Longest branch slug derived from an issue title, before the number prefix.
/// Matches the desktop so both apps suggest the same branch for one issue.
const int _maxBranchSlugLength = 48;

String mobileIssueWorkspaceName(MobileIssueDetails issue) => issue.title.trim();

String mobileIssueBranchName(MobileIssueDetails issue) {
  final words = issue.title
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
  return buffer.isEmpty ? '${issue.number}' : '${issue.number}-$buffer';
}

String mobileIssuePrompt(MobileIssueDetails issue) {
  final body = issue.body?.trim();
  return <String>[
    issue.title.trim(),
    if (body != null && body.isNotEmpty) body,
    issue.url,
  ].join('\n\n');
}

/// Parses a user-entered review reference into a review number. Accepts a bare
/// number, a `#123` form, or a GitHub/GitLab/Azure DevOps review URL. Returns
/// null when no number can be extracted.
int? parseReviewReference(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final plain = RegExp(r'^#?(\d+)$').firstMatch(trimmed);
  if (plain != null) {
    return int.tryParse(plain.group(1)!);
  }
  // GitHub: /pull/123 ; GitLab: /-/merge_requests/123 ; Azure: /pullrequest/123
  final url = RegExp(
    r'/(?:pull|pullrequest|-/merge_requests)/(\d+)',
  ).firstMatch(trimmed);
  if (url != null) {
    return int.tryParse(url.group(1)!);
  }
  return null;
}

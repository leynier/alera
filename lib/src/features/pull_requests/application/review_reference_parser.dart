/// Parses a user-entered review reference into a review number. Accepts a bare
/// number, a `#123` form, or a GitHub/Azure DevOps pull-request URL. Returns
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
  // GitHub: /pull/123 ; Azure DevOps: /pullrequest/123
  final url = RegExp(r'/(?:pull|pullrequest)/(\d+)').firstMatch(trimmed);
  if (url != null) {
    return int.tryParse(url.group(1)!);
  }
  return null;
}

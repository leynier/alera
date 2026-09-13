import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'linked_issue_link_result.mapper.dart';

/// Why an issue could not be fetched. `code` is one of `invalidUrl`,
/// `unsupported`, `cliMissing`, `notAuthenticated`, `notFound` or `failed`.
@MappableClass()
class const IssueFetchFailure({required this.code, required this.message})
    with IssueFetchFailureMappable {
  final String code;
  final String message;

  /// A URL no provider recognizes: expected for Jira, Linear and the like.
  bool get isUnsupported => code == 'unsupported';
}

/// What `linkedIssue.link` and `linkedIssue.refresh` answer: the stored link
/// always, the fresh issue when the fetch worked, and why it did not otherwise.
@MappableClass()
class const LinkedIssueLinkResult({
  required this.linkedIssue,
  this.issue,
  this.fetchError,
}) with LinkedIssueLinkResultMappable {
  final LinkedIssue linkedIssue;
  final IssueDetails? issue;
  final IssueFetchFailure? fetchError;

  factory fromJson(Map<String, Object?> json) =>
      LinkedIssueLinkResultMapper.fromMap(Map<String, dynamic>.from(json));
}

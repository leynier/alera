import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_link_result.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_snapshot.dart';

/// Per-workspace linked issues and issue fetching. The runtime host owns both:
/// it stores the links and reads issues through each forge's CLI.
abstract interface class LinkedIssueRepository {
  /// Whether the connected host advertises `linkedIssuesV1`. Callers hide the
  /// feature rather than send verbs an older host would reject.
  Future<bool> isSupported();

  /// Support plus every linked issue, refreshed on host broadcasts and on
  /// reconnect, so a host upgrade shows up without an app restart.
  Stream<LinkedIssueSnapshot> watchSnapshot();

  Future<Map<String, LinkedIssue>> listAll();

  /// Stores [url] as the workspace's issue, then fetches its metadata. A failed
  /// fetch is reported in the result, never thrown: the link is kept.
  Future<LinkedIssueLinkResult> link(String workspaceId, String url);

  Future<LinkedIssueLinkResult> refresh(String workspaceId);

  Future<void> unlink(String workspaceId);

  /// Fetches an issue without linking it. Throws when it cannot be read.
  Future<IssueDetails> fetch(String url);
}

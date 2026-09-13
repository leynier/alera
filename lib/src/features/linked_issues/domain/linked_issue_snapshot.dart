import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';

/// What the sidebar and forms need to render linked issues synchronously:
/// whether the host supports them, and every link keyed by workspace id.
class const LinkedIssueSnapshot({
  final bool supported = false,
  final Map<String, LinkedIssue> byWorkspace = const <String, LinkedIssue>{},
});

import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/domain/issue_state.dart';
import 'package:alera/src/features/linked_issues/domain/issue_workspace_identity.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_link_result.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_snapshot.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter_test/flutter_test.dart';

IssueDetails _issue({
  String title = 'feat: link an issue to a workspace',
  String? body = 'Problem\n\nDetails',
  int number = 758,
}) => IssueDetails(
  provider: .github,
  url: 'https://github.com/leynier/alera/issues/758',
  number: number,
  title: title,
  state: .open,
  body: body,
);

void main() {
  group('LinkedIssue wire format', () {
    test('reads the record the host stores after a fetch', () {
      final issue = LinkedIssue.fromJson(<String, Object?>{
        'workspaceId': 'w1',
        'url': 'https://dev.azure.com/o/p/_workitems/edit/42',
        'provider': 'azureDevops',
        'repository': 'o/p',
        'number': 42,
        'title': 'Checkout fails',
        'state': 'closed',
        'stateLabel': 'Resolved',
        'fetchedAt': '2026-09-12T21:18:27.188Z',
        'fetchError': null,
        'linkedAt': '2026-09-12T21:18:27.187Z',
      });
      expect(issue.provider, GitHostingProvider.azureDevops);
      expect(issue.state, IssueState.closed);
      expect(issue.reference, '#42');
      expect(issue.displayState, 'Resolved');
      expect(issue.isFetchable, isTrue);
      expect(issue.fetchedAt, DateTime.utc(2026, 9, 12, 21, 18, 27, 188));
    });

    test('keeps a URL-only link readable', () {
      final issue = LinkedIssue.fromJson(<String, Object?>{
        'workspaceId': 'w1',
        'url': 'https://example.atlassian.net/browse/ABC-1',
        'linkedAt': '2026-09-12T21:18:27Z',
      });
      expect(issue.provider, isNull);
      expect(issue.isFetchable, isFalse);
      expect(issue.reference, 'https://example.atlassian.net/browse/ABC-1');
      expect(issue.displayState, isNull);
      expect(
        LinkedIssue(
          workspaceId: 'w1',
          url: 'u',
          linkedAt: DateTime.utc(2026),
          state: .open,
        ).displayState,
        'Open',
      );
    });

    test('decodes link results with and without a fetch failure', () {
      final linked = <String, Object?>{
        'workspaceId': 'w1',
        'url': 'https://github.com/leynier/alera/issues/758',
        'provider': 'github',
        'number': 758,
        'linkedAt': '2026-09-12T21:18:27Z',
      };
      final failed = LinkedIssueLinkResult.fromJson(<String, Object?>{
        'linkedIssue': linked,
        'issue': null,
        'fetchError': <String, Object?>{
          'code': 'cliMissing',
          'message': 'The GitHub CLI (gh) is not available.',
        },
      });
      expect(failed.issue, isNull);
      expect(failed.fetchError!.isUnsupported, isFalse);
      expect(
        const IssueFetchFailure(code: 'unsupported', message: '').isUnsupported,
        isTrue,
      );

      final fetched = LinkedIssueLinkResult.fromJson(<String, Object?>{
        'linkedIssue': linked,
        'issue': <String, Object?>{
          'provider': 'gitlab',
          'url': 'https://gitlab.com/a/b/-/issues/3',
          'repository': 'a/b',
          'number': 3,
          'title': 'Fix it',
          'state': 'unknown',
          'stateLabel': null,
          'body': null,
          'labels': <String>['bug'],
          'assignees': <String>['dev'],
          'author': 'lead',
          'createdAt': '2020-07-24T23:57:04Z',
          'updatedAt': null,
        },
        'fetchError': null,
      });
      expect(fetched.fetchError, isNull);
      expect(fetched.issue!.provider, GitHostingProvider.gitlab);
      expect(fetched.issue!.displayState, 'Unknown');
      expect(fetched.issue!.labels, <String>['bug']);
      expect(fetched.linkedIssue.number, 758);
    });

    test('labels every state and snapshot defaults to unsupported', () {
      expect(IssueState.values.map((state) => state.label), <String>[
        'Open',
        'Closed',
        'Unknown',
      ]);
      const snapshot = LinkedIssueSnapshot();
      expect(snapshot.supported, isFalse);
      expect(snapshot.byWorkspace, isEmpty);
      expect(IssueDetails.fromJson(_issue().toMap()).displayState, 'Open');
    });
  });

  group('workspace identity from an issue', () {
    test('uses the title as name and number plus slug as branch', () {
      final issue = _issue();
      expect(issueWorkspaceName(issue), 'feat: link an issue to a workspace');
      expect(issueBranchName(issue), '758-feat-link-an-issue-to-a-workspace');
    });

    test('cuts long slugs at a word boundary and handles symbol titles', () {
      final long = _issue(
        title: 'Make the terminal restore fast enough for very large scrollback buffers please',
      );
      final branch = issueBranchName(long);
      expect(branch, startsWith('758-make-the-terminal-restore'));
      expect(branch.length, lessThanOrEqualTo(4 + 48));
      expect(branch.endsWith('-'), isFalse);
      expect(issueBranchName(_issue(title: '!!!')), '758');
      final word = 'a' * 80;
      expect(issueBranchName(_issue(title: word)), '758-${'a' * 48}');
    });

    test('builds the starting prompt from title, body and link', () {
      expect(
        issuePrompt(_issue()),
        'feat: link an issue to a workspace\n\nProblem\n\nDetails\n\n'
        'https://github.com/leynier/alera/issues/758',
      );
      expect(
        issuePrompt(_issue(body: '  ')),
        'feat: link an issue to a workspace\n\n'
        'https://github.com/leynier/alera/issues/758',
      );
    });
  });
}

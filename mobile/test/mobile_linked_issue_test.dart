import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_issue_workspace_identity.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:alera_mobile/src/features/linked_issues/infra/mobile_runtime_linked_issue_requests.dart';
import 'package:alera_mobile/src/features/linked_issues/presentation/mobile_issue_url_field.dart';
import 'package:alera_mobile/src/features/linked_issues/presentation/mobile_link_issue_dialog.dart';
import 'package:alera_mobile/src/features/linked_issues/presentation/mobile_linked_issue_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://github.com/leynier/alera/issues/758';

MobileIssueDetails _details({String? body = 'Body'}) => MobileIssueDetails(
  url: _url,
  number: 758,
  title: 'feat: link an issue to a workspace',
  state: 'open',
  body: body,
);

void main() {
  test('parses linked issues and fetch results from the runtime', () {
    final issue = MobileLinkedIssue.fromJson(<String, Object?>{
      'workspaceId': 'w1',
      'url': _url,
      'provider': 'github',
      'number': 758,
      'title': 'Link an issue',
      'state': 'open',
      'linkedAt': '2026-09-12T00:00:00Z',
    });
    expect(issue.isFetchable, isTrue);
    expect(issue.reference, '#758');
    expect(issue.displayState, 'Open');
    expect(issue.isOpen, isTrue);
    expect(mobileLinkedIssueTooltip(issue), 'Issue #758: Link an issue\nOpen');

    final urlOnly = MobileLinkedIssue.fromJson(<String, Object?>{
      'workspaceId': 'w1',
      'url': 'https://example.atlassian.net/browse/X-1',
      'fetchError': 'gh is signed out',
      'state': 'closed',
      'stateLabel': 'Resolved',
    });
    expect(urlOnly.isFetchable, isFalse);
    expect(urlOnly.isClosed, isTrue);
    expect(
      mobileLinkedIssueTooltip(urlOnly),
      'Issue https://example.atlassian.net/browse/X-1\nResolved\n'
      'Details unavailable: gh is signed out',
    );

    final result = MobileLinkIssueResult.fromJson(<String, Object?>{
      'linkedIssue': <String, Object?>{'workspaceId': 'w1', 'url': _url},
      'fetchError': <String, Object?>{
        'code': 'unsupported',
        'message': 'No issue provider recognizes it.',
      },
    });
    expect(result.fetchErrorCode, 'unsupported');
    expect(mobileLinkIssueMessage(result), contains('only the link is kept'));
    expect(
      mobileLinkIssueMessage(
        const MobileLinkIssueResult(
          linkedIssue: MobileLinkedIssue(workspaceId: 'w1', url: _url),
        ),
      ),
      'Issue linked',
    );
    expect(
      mobileLinkIssueMessage(
        const MobileLinkIssueResult(
          linkedIssue: MobileLinkedIssue(workspaceId: 'w1', url: _url),
          fetchErrorCode: 'cliMissing',
          fetchErrorMessage: 'Install gh.',
        ),
      ),
      'Issue linked, but its details could not be read: Install gh.',
    );
    final details = MobileIssueDetails.fromJson(<String, Object?>{
      'url': _url,
      'number': 758,
      'state': 'unknown',
    });
    expect(details.displayState, 'Unknown');
    expect(details.title, isEmpty);
  });

  test('suggests the same workspace identity as the desktop', () {
    expect(
      mobileIssueWorkspaceName(_details()),
      'feat: link an issue to a workspace',
    );
    expect(
      mobileIssueBranchName(_details()),
      '758-feat-link-an-issue-to-a-workspace',
    );
    expect(
      mobileIssuePrompt(_details()),
      'feat: link an issue to a workspace\n\nBody\n\n$_url',
    );
    expect(
      mobileIssuePrompt(_details(body: null)),
      'feat: link an issue to a workspace\n\n$_url',
    );
  });

  test(
    'sends linked issue verbs only through the advertised capability',
    () async {
      final client = _FakeRequests(<String>{linkedIssuesCapability});
      expect(client.supportsLinkedIssues, isTrue);
      expect(_FakeRequests(const <String>{}).supportsLinkedIssues, isFalse);

      final links = await client.listLinkedIssues();
      expect(links.single.workspaceId, 'w1');
      final linked = await client.linkIssue('w1', _url);
      expect(linked.linkedIssue.url, _url);
      await client.unlinkIssue('w1');
      final fetched = await client.fetchIssue(_url);
      expect(fetched.number, 758);
      expect(client.calls, <String>[
        'linkedIssue.list',
        'linkedIssue.link {workspaceId: w1, url: $_url} timeout',
        'linkedIssue.remove {workspaceId: w1}',
        'issue.fetch {url: $_url} timeout',
      ]);
    },
  );

  testWidgets('the URL field resolves and reports the issue', (tester) async {
    final controller = TextEditingController();
    MobileIssueDetails? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileIssueUrlField(
            controller: controller,
            fetchIssue: (url) async => url.endsWith('758')
                ? _details()
                : throw StateError('not found'),
            onResolved: (issue) => resolved = issue,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), _url);
    await tester.pump();
    expect(find.text('Resolving issue'), findsOneWidget);
    await tester.pump(mobileIssueUrlResolveDelay);
    await tester.pump();
    expect(resolved?.number, 758);
    expect(find.textContaining('#758 · Open'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'https://example.com/1');
    await tester.pump(mobileIssueUrlResolveDelay);
    await tester.pump();
    expect(find.textContaining('The link will still be saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _FakeRequests with MobileRuntimeLinkedIssueRequests {
  _FakeRequests(this.runtimeCapabilities);

  @override
  final Set<String> runtimeCapabilities;
  final List<String> calls = <String>[];

  void _record(String type, Map<String, Object?> payload, Duration? timeout) {
    calls.add(
      '$type${payload.isEmpty ? '' : ' $payload'}${timeout == null ? '' : ' timeout'}',
    );
  }

  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    _record(type, payload, timeout);
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    _record(type, payload, timeout);
    const linked = <String, Object?>{'workspaceId': 'w1', 'url': _url};
    return switch (type) {
      'linkedIssue.list' => <String, Object?>{
        'items': <Object?>[linked],
      },
      'linkedIssue.link' => <String, Object?>{'linkedIssue': linked},
      _ => <String, Object?>{
        'url': _url,
        'number': 758,
        'title': 'Link an issue',
        'state': 'open',
      },
    };
  }
}

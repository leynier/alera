import 'dart:async';

import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:alera/src/features/linked_issues/presentation/issue_url_field.dart';
import 'package:alera/src/features/linked_issues/presentation/workspace_linked_issue_indicator.dart';
import 'package:alera/src/features/linked_issues/presentation/workspace_linked_issue_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _linkedAt = DateTime.utc(2026, 9, 12);

IssueDetails _details() => const IssueDetails(
  provider: .github,
  url: 'https://github.com/leynier/alera/issues/758',
  number: 758,
  title: 'Link an issue',
  state: .open,
);

List<String> _labels(List<PopupMenuEntry<String>> entries) => <String>[
  for (final entry in entries) (entry as AleraDropdownEntry<String>).label,
];

void main() {
  group('context menu entries', () {
    test('hide everything when the host cannot link issues', () {
      expect(
        linkedIssueMenuEntries(supported: false, linkedIssue: null),
        isEmpty,
      );
    });

    test('offer linking without an issue and managing it with one', () {
      expect(
        _labels(linkedIssueMenuEntries(supported: true, linkedIssue: null)),
        <String>['Link Issue'],
      );
      final linked = LinkedIssue(
        workspaceId: 'w1',
        url: 'https://github.com/leynier/alera/issues/758',
        linkedAt: _linkedAt,
      );
      expect(
        _labels(linkedIssueMenuEntries(supported: true, linkedIssue: linked)),
        <String>[
          'Open Issue in Browser',
          'Change Linked Issue',
          'Unlink Issue',
        ],
      );
      expect(isLinkedIssueMenuAction(unlinkIssueMenuAction), isTrue);
      expect(isLinkedIssueMenuAction('rename'), isFalse);
      expect(isLinkedIssueMenuAction(null), isFalse);
    });
  });

  group('row tooltip', () {
    test('describes a fetched issue', () {
      final issue = LinkedIssue(
        workspaceId: 'w1',
        url: 'https://github.com/leynier/alera/issues/758',
        provider: .github,
        number: 758,
        title: 'Link an issue',
        state: .open,
        linkedAt: _linkedAt,
      );
      expect(
        workspaceLinkedIssueTooltip(issue),
        'Issue #758: Link an issue\nOpen\nhttps://github.com/leynier/alera/issues/758',
      );
    });

    test('explains missing details', () {
      final failed = LinkedIssue(
        workspaceId: 'w1',
        url: 'https://github.com/leynier/alera/issues/758',
        provider: .github,
        number: 758,
        fetchError: 'gh is not authenticated.',
        linkedAt: _linkedAt,
      );
      expect(
        workspaceLinkedIssueTooltip(failed),
        'Issue #758\nDetails unavailable: gh is not authenticated.',
      );
      final urlOnly = LinkedIssue(
        workspaceId: 'w1',
        url: 'https://example.atlassian.net/browse/ABC-1',
        linkedAt: _linkedAt,
      );
      expect(
        workspaceLinkedIssueTooltip(urlOnly),
        'Issue https://example.atlassian.net/browse/ABC-1\n'
        'No provider can read this tracker, so only the link is kept',
      );
    });
  });

  group('IssueUrlField', () {
    testWidgets('resolves after a pause and reports the issue', (tester) async {
      final controller = TextEditingController();
      final requested = <String>[];
      IssueDetails? resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IssueUrlField(
              controller: controller,
              fetchIssue: (url) async {
                requested.add(url);
                return _details();
              },
              onResolved: (issue) => resolved = issue,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://github.com/leynier/alera/issues/7',
      );
      await tester.enterText(
        find.byType(TextField),
        'https://github.com/leynier/alera/issues/758',
      );
      await tester.pump();
      expect(find.text('Resolving issue'), findsOneWidget);
      await tester.pump(issueUrlResolveDelay);
      await tester.pump();
      expect(requested, <String>[
        'https://github.com/leynier/alera/issues/758',
      ]);
      expect(resolved?.number, 758);
      expect(find.text('#758 · Open · Link an issue'), findsOneWidget);

      controller.clear();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('issue-url-field-status')),
        findsNothing,
      );
      controller.dispose();
    });

    testWidgets('shows a failed resolve as a non-blocking warning', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'https://example.com/x');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IssueUrlField(
              controller: controller,
              fetchIssue: (_) async =>
                  throw StateError('No issue provider recognizes it.'),
            ),
          ),
        ),
      );
      await tester.pump(issueUrlResolveDelay);
      await tester.pump();
      expect(
        find.textContaining('The link will still be saved.'),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('ignores a result for a URL that was replaced', (tester) async {
      final controller = TextEditingController(
        text: 'https://github.com/o/r/issues/1',
      );
      final pending = Completer<IssueDetails>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IssueUrlField(
              controller: controller,
              fetchIssue: (url) => url.endsWith('/1')
                  ? pending.future
                  : Future<IssueDetails>.value(_details()),
            ),
          ),
        ),
      );
      await tester.pump(issueUrlResolveDelay);
      controller.text = 'https://github.com/o/r/issues/758';
      await tester.pump(issueUrlResolveDelay);
      await tester.pump();
      pending.complete(
        const IssueDetails(
          provider: .github,
          url: 'u',
          number: 1,
          title: 'Old',
          state: .closed,
        ),
      );
      await tester.pump();
      expect(find.textContaining('Old'), findsNothing);
      expect(find.text('#758 · Open · Link an issue'), findsOneWidget);
      controller.dispose();
    });
  });
}

import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_repository.dart';
import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_link_result.dart';
import 'package:alera/src/features/linked_issues/presentation/link_issue_dialog.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/background_operation_cards.dart';
import 'package:alera/src/features/workbench/presentation/workspace_graph_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026);
final _workspace = Workspace(
  id: 'w',
  projectId: 'p',
  name: 'Workspace',
  path: '/repo',
  createdAt: _now,
  updatedAt: _now,
  kind: WorkspaceKind.linked,
  status: WorkspaceStatus.active,
);

class _Issues implements LinkedIssueRepository {
  final pending = Completer<LinkedIssueLinkResult>();
  @override
  Future<LinkedIssueLinkResult> link(String workspaceId, String url) =>
      pending.future;
  @override
  Future<IssueDetails> fetch(String url) async => IssueDetails(
    provider: .github,
    url: url,
    number: 1,
    title: 'Issue',
    state: .open,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester tester,
  void Function(BuildContext) open,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: aleraDarkTheme,
        builder: (context, child) => Stack(
          children: [
            child!,
            const Align(
              alignment: Alignment.bottomRight,
              child: BackgroundOperationCards(),
            ),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'linking releases its dialog and restores the URL after failure',
    (tester) async {
      final issues = _Issues();
      const url = 'https://github.com/acme/repo/issues/1';
      await _open(
        tester,
        (context) => showLinkIssueDialog(
          context,
          repository: issues,
          workspaceId: 'w',
          workspaceName: 'Workspace',
          initialUrl: url,
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('link-issue-submit')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey<String>('link-issue-submit')),
        findsNothing,
      );
      issues.pending.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text(url), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('link-issue-submit')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tag creation can finish in the background and retain its failure',
    (tester) async {
      final pending = Completer<WorkspaceTag>();
      await _open(
        tester,
        (context) => showWorkspaceTagsDialog(
          context: context,
          workspace: _workspace,
          tags: [],
          onCreateTag: (_) => pending.future,
          onDeleteTag: (_) async {},
        ),
      );
      await tester.enterText(find.byType(TextField), 'My Tag');
      await tester.tap(find.text('Create Tag'));
      await tester.pump();
      await tester.tap(find.text('Run In Background'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Manage Tags'), findsNothing);
      pending.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

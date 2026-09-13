import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/presentation/issue_url_field.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://github.com/leynier/alera/issues/758';

void main() {
  testWidgets('a resolved issue fills an empty branch and name', (
    tester,
  ) async {
    final submitted = <ManualWorkspaceCreateRequest>[];
    await _pumpDialog(tester, onEnqueue: submitted.add);
    await _openSettings(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Issue URL'), _url);
    await tester.pump(issueUrlResolveDelay);
    await tester.pumpAndSettle();

    expect(
      _fieldText(tester, 'New Branch Name *'),
      '758-link-an-issue-to-a-workspace',
    );
    expect(
      _fieldText(tester, 'Workspace Name (Optional)'),
      'Link an issue to a workspace',
    );

    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();
    expect(submitted.single.issueUrl, _url);
    expect(submitted.single.newBranchName, '758-link-an-issue-to-a-workspace');
    expect(submitted.single.name, 'Link an issue to a workspace');
  });

  testWidgets('a resolved issue never overwrites what the user typed', (
    tester,
  ) async {
    await _pumpDialog(tester, onEnqueue: (_) {});
    await _openSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/mine',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace Name (Optional)'),
      'Mine',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Issue URL'), _url);
    await tester.pump(issueUrlResolveDelay);
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'New Branch Name *'), 'feature/mine');
    expect(_fieldText(tester, 'Workspace Name (Optional)'), 'Mine');
  });

  testWidgets('the field is hidden when the host cannot link issues', (
    tester,
  ) async {
    await _pumpDialog(tester, onEnqueue: (_) {}, fetchIssue: null);
    await _openSettings(tester);
    expect(find.widgetWithText(TextField, 'Issue URL'), findsNothing);
  });
}

String _fieldText(WidgetTester tester, String label) {
  final field = tester.widget<TextField>(find.widgetWithText(TextField, label));
  return field.controller!.text;
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required void Function(ManualWorkspaceCreateRequest request) onEnqueue,
  Future<IssueDetails> Function(String url)? fetchIssue = _fetch,
}) async {
  final now = DateTime.utc(2026, 9, 12);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CreateWorkspaceDialog(
                  projects: <Project>[project],
                  loadBranches: (_) async => const <String>['main'],
                  checkBranchExists: (_, _) async => false,
                  getProjectActiveBranch: (_) => null,
                  getProjectWorkspaceBranches: (_) => const <String>{},
                  fetchIssue: fetchIssue,
                  enqueueCreate: (request) {
                    onEnqueue(request);
                    return Future<void>.value();
                  },
                  onCreateWorkspace: ({
                    required project,
                    required sourceBranch,
                    required newBranchName,
                    required reuseExistingBranch,
                    name,
                    parentWorkspaceId,
                    hostId,
                    issueUrl,
                  }) async => throw UnimplementedError(),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<IssueDetails> _fetch(String url) async => const IssueDetails(
  provider: .github,
  url: _url,
  number: 758,
  title: 'Link an issue to a workspace',
  state: .open,
);

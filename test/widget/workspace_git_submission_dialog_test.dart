import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_submission_dialog.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const snapshot = GitWorkspaceComparison(
  baseRef: null,
  baseOid: 'base',
  headOid: 'head',
  headRef: 'refs/heads/feature',
  treeOid: 'tree',
  indexOid: 'index',
  added: 2,
  removed: 0,
  entries: [
    GitChangeEntry(path: 'selected.txt', area: .unstaged, status: .modified),
    GitChangeEntry(path: 'excluded.txt', area: .staged, status: .modified),
  ],
);

Future<void> openDialog(
  WidgetTester tester, {
  Future<String> Function(List<String>)? generate,
  void Function(WorkspaceGitSubmission?)? result,
  void Function(String)? openFile,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result?.call(
              await showDialog<WorkspaceGitSubmission>(
                context: context,
                builder: (_) => WorkspaceGitSubmissionDialog(
                  path: '/repo',
                  snapshot: snapshot,
                  action: .commit,
                  branch: 'feature',
                  baseBranch: 'main',
                  isDefaultBranch: false,
                  provider: null,
                  onGenerate: generate,
                  onOpenFile: openFile,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('review approves only selected full files and edited message', (
    tester,
  ) async {
    WorkspaceGitSubmission? result;
    final generated = <List<String>>[];
    final opened = <String>[];
    await openDialog(
      tester,
      result: (value) => result = value,
      openFile: opened.add,
      generate: (files) async {
        generated.add(files);
        return 'fix: generated';
      },
    );
    expect(generated.single, ['selected.txt', 'excluded.txt']);
    await tester.tap(find.byType(AleraCheckbox).at(2));
    await tester.tap(find.text('Generate Message'));
    await tester.pumpAndSettle();
    expect(generated.last, ['selected.txt']);
    await tester.tap(find.text('selected.txt'));
    expect(opened, ['selected.txt']);
    await tester.enterText(
      find.descendant(
        of: find.byType(AleraTextField),
        matching: find.byType(TextField),
      ),
      'fix: manually reviewed',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(result?.files, ['selected.txt']);
    expect(result?.message, 'fix: manually reviewed');
    expect(identical(result?.snapshot, snapshot), isTrue);
  });
  testWidgets('cancel returns no submission', (tester) async {
    var called = false;
    await openDialog(
      tester,
      result: (value) {
        called = true;
        expect(value, isNull);
      },
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });
}

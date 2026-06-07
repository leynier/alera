import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

void main() {
  testWidgets('git diff panel hides zero-valued line counts', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
            added: 12,
            removed: 0,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gitBackendProvider.overrideWithValue(backend)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 420,
              child: WorkspaceGitDiffPanel(
                workspace: _workspace(),
                viewMode: GitDiffViewMode.flat,
                onViewModeChanged: (_) {},
                onOpenGitDiff: ({area, relativePath, required scope}) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+12'), findsOneWidget);
    expect(find.text('-0'), findsNothing);
  });

  testWidgets('git diff panel shows relative paths in flat rows', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
          GitChangeEntry(
            path: 'test/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gitBackendProvider.overrideWithValue(backend)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 420,
              child: WorkspaceGitDiffPanel(
                workspace: _workspace(),
                viewMode: GitDiffViewMode.flat,
                onViewModeChanged: (_) {},
                onOpenGitDiff: ({area, relativePath, required scope}) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lib/foo.dart'), findsOneWidget);
    expect(find.text('test/foo.dart'), findsOneWidget);
    expect(find.text('foo.dart'), findsNothing);
  });
}

Workspace _workspace() {
  final now = DateTime.utc(2026, 6, 6);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Main',
    path: '/tmp/project',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

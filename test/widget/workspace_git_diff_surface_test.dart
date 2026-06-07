import 'package:alera/src/app/providers.dart'
    show WorkbenchController, workbenchControllerProvider;
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_surface.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

void main() {
  testWidgets('diff surface caps rendered line previews', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/large.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            patch: List<String>.generate(
              6005,
              (index) => '+line $index',
            ).join('\n'),
            added: 6005,
            removed: 0,
          ),
        ],
      );

    await _pumpDiffSurface(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.text('+line 0'), findsOneWidget);
    expect(find.text('+line 5000'), findsNothing);
    expect(find.text('+line 6000'), findsNothing);
    expect(find.text('+6005'), findsOneWidget);
    expect(find.text('-0'), findsNothing);

    await tester.dragUntilVisible(
      find.text('Diff line preview truncated.'),
      find.byType(ListView),
      const Offset(0, -1600),
      maxIteration: 80,
    );
    await tester.pumpAndSettle();

    expect(find.text('Diff line preview truncated.'), findsOneWidget);
    expect(find.text('+line 5000'), findsNothing);
    expect(find.text('+line 6000'), findsNothing);
  });

  testWidgets('diff surface disables opening deleted files', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/deleted.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.deleted,
            patch: '-old',
            added: 0,
            removed: 1,
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(
        filePath: 'lib/deleted.dart',
        title: 'deleted.dart staged',
        area: GitChangeArea.staged,
      ),
    );
    await tester.pumpAndSettle();

    expect(_openFileButton(tester).onPressed, isNull);
    expect(
      find.byTooltip('File is not available in working tree'),
      findsOneWidget,
    );
  });

  testWidgets('diff surface enables opening modified files', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            patch: '+new',
            added: 1,
            removed: 0,
          ),
        ],
      );

    await _pumpDiffSurface(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(_openFileButton(tester).onPressed, isNotNull);
    expect(find.byTooltip('Open file'), findsOneWidget);
  });

  testWidgets('diff surface disables opening rename-out old paths', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/foo.dart',
            oldPath: 'lib/foo.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.renamed,
            patch: 'rename from packages/app/lib/foo.dart',
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(
        filePath: 'lib/foo.dart',
        title: 'foo.dart staged',
        area: GitChangeArea.staged,
      ),
    );
    await tester.pumpAndSettle();

    expect(_openFileButton(tester).onPressed, isNull);
    expect(
      find.byTooltip('File is not available in working tree'),
      findsOneWidget,
    );
  });

  testWidgets('diff surface enables opening in-workspace renames', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/new.dart',
            oldPath: 'lib/old.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.renamed,
            patch: 'rename to lib/new.dart',
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(
        filePath: 'lib/new.dart',
        title: 'new.dart staged',
        area: GitChangeArea.staged,
      ),
    );
    await tester.pumpAndSettle();

    expect(_openFileButton(tester).onPressed, isNotNull);
    expect(find.byTooltip('Open file'), findsOneWidget);
  });

  testWidgets('diff surface opens loaded rename target path', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/new.dart',
            oldPath: 'lib/old.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.renamed,
            patch: 'rename to lib/new.dart',
          ),
        ],
      );
    final controller = _GitDiffSurfaceTestController();

    await _pumpDiffSurface(
      tester,
      backend: backend,
      controller: controller,
      tab: _diffTab(
        filePath: 'lib/old.dart',
        title: 'old.dart staged',
        area: GitChangeArea.staged,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open file'));
    await tester.pump();

    expect(controller.openedRelativePaths, <String>['lib/new.dart']);
  });

  testWidgets('diff surface hides zero-valued header stats', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/added.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
            patch: '+new',
            added: 3,
            removed: 0,
          ),
          GitDiffFile(
            path: 'lib/deleted.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.deleted,
            patch: '-old',
            added: 0,
            removed: 2,
          ),
        ],
      );

    await _pumpDiffSurface(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.text('+3'), findsOneWidget);
    expect(find.text('-2'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    expect(find.text('-0'), findsNothing);
  });
}

Future<void> _pumpDiffSurface(
  WidgetTester tester, {
  required FakeGitBackend backend,
  WorkbenchController? controller,
  WorkspaceTabRecord? tab,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(backend),
        if (controller != null)
          workbenchControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: WorkspaceGitDiffSurface(
              workspace: _workspace(),
              tab: tab ?? _diffTab(),
            ),
          ),
        ),
      ),
    ),
  );
}

IconButton _openFileButton(WidgetTester tester) {
  final finder = find.ancestor(
    of: find.byIcon(Icons.open_in_new),
    matching: find.byType(IconButton),
  );
  return tester.widget<IconButton>(finder);
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

WorkspaceTabRecord _diffTab({
  String filePath = 'lib/large.dart',
  String title = 'large.dart unstaged',
  GitChangeArea area = GitChangeArea.unstaged,
}) {
  final now = DateTime.utc(2026, 6, 6);
  return WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: 'workspace-1',
    kind: WorkspaceTabKind.gitDiff,
    title: title,
    createdAt: now,
    updatedAt: now,
    payload: <String, Object?>{
      workspaceTabGitDiffScopePayloadKey: 'file',
      workspaceTabFilePathPayloadKey: filePath,
      workspaceTabGitDiffAreaPayloadKey: area.key,
    },
  );
}

class _GitDiffSurfaceTestController extends WorkbenchController {
  final List<String> openedRelativePaths = <String>[];

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  Future<WorkspaceTabRecord> openEditorTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    openedRelativePaths.add(relativePath);
    final now = DateTime.utc(2026, 6, 6);
    return WorkspaceTabRecord(
      id: 'editor-${openedRelativePaths.length}',
      workspaceId: workspace.id,
      kind: WorkspaceTabKind.editor,
      title: relativePath.split('/').last,
      createdAt: now,
      updatedAt: now,
      payload: <String, Object?>{workspaceTabFilePathPayloadKey: relativePath},
    );
  }
}

import 'package:alera/src/app/providers.dart'
    show WorkbenchController, workbenchControllerProvider;
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_surface.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../unit/fake_git_backend.dart';

part 'workspace_git_diff_surface_test_support.dart';

void main() {
  testWidgets('diff surface caps rendered line previews', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/large.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            lines: List<GitDiffLine>.generate(
              5000,
              (index) => GitDiffLine.addition('+line $index'),
            ),
            added: 6005,
            removed: 0,
            linePreviewTruncated: true,
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
            lines: <GitDiffLine>[GitDiffLine.deletion('-old')],
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

  testWidgets('diff surface disables opening gitlink diffs', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'modules/sample',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            lines: <GitDiffLine>[
              GitDiffLine.addition('+Subproject commit abc123'),
            ],
            added: 1,
            removed: 1,
            isGitlink: true,
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(
        filePath: 'modules/sample',
        title: 'sample unstaged',
        area: GitChangeArea.unstaged,
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
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
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
            lines: <GitDiffLine>[
              GitDiffLine.header('rename from packages/app/lib/foo.dart'),
            ],
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
            lines: <GitDiffLine>[GitDiffLine.header('rename to lib/new.dart')],
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
            lines: <GitDiffLine>[GitDiffLine.header('rename to lib/new.dart')],
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

  testWidgets('diff surface scopes nested git roots and opens workspace path', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
          ),
        ],
      );
    final controller = _GitDiffSurfaceTestController();

    await _pumpDiffSurface(
      tester,
      backend: backend,
      controller: controller,
      tab: _diffTab(
        filePath: 'packages/app/lib/main.dart',
        title: 'main.dart unstaged',
        area: GitChangeArea.unstaged,
        gitDiffRoot: 'packages/app',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'diff').single.args,
      <String, Object?>{
        'path': p.join('/tmp/project', 'packages', 'app'),
        'filePath': 'lib/main.dart',
        'area': GitChangeArea.unstaged,
      },
    );

    await tester.tap(find.byTooltip('Open file'));
    await tester.pump();

    expect(controller.openedRelativePaths, <String>[
      'packages/app/lib/main.dart',
    ]);
  });

  testWidgets('diff surface keeps scoped file-all outside root empty', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffAllResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'unrelated.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+unrelated')],
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(
        scope: WorkspaceGitDiffScope.fileAll,
        filePath: 'docs/main.dart',
        title: 'main.dart changes',
        area: null,
        gitDiffRoot: 'packages/app',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No diff available.'), findsOneWidget);
    expect(backend.calls.where((call) => call.method == 'diffAll'), isEmpty);
  });

  testWidgets('diff surface hides zero-valued header stats', (tester) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/added.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 3,
            removed: 0,
          ),
          GitDiffFile(
            path: 'lib/deleted.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.deleted,
            lines: <GitDiffLine>[GitDiffLine.deletion('-old')],
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

  testWidgets('diff surface loads commit diffs from commit payload', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitCommitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            sourceLabel: 'Commit',
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(
        source: WorkspaceGitDiffSource.commit,
        filePath: 'packages/app/lib/main.dart',
        title: 'main.dart abc1234',
        scope: WorkspaceGitDiffScope.file,
        area: null,
        gitDiffRoot: 'packages/app',
        commitOid: 'abc123456789',
        parentOid: 'def987654321',
        compareRef: 'abc1234',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'commitDiff').single.args,
      <String, Object?>{
        'path': p.join('/tmp/project', 'packages', 'app'),
        'commitOid': 'abc123456789',
        'parentOid': 'def987654321',
        'filePath': 'lib/main.dart',
        'oldPath': null,
      },
    );
    expect(find.text('Commit · lib/main.dart'), findsOneWidget);
    expect(_openFileButton(tester).onPressed, isNull);
  });
}

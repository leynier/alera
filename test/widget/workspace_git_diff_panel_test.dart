import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
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

  testWidgets('stage all dispatches workspace scoped stage', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stage all'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'stage').single.args,
      <String, Object?>{'path': '/tmp/project', 'filePath': null},
    );
  });

  testWidgets('file actions stage and unstage selected paths', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stage').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unstage').first);
    await tester.pumpAndSettle();

    expect(
      backend.calls
          .where((call) => call.method == 'stage')
          .map((call) => call.args['filePath']),
      contains('lib/new.dart'),
    );
    expect(
      backend.calls
          .where((call) => call.method == 'unstage')
          .map((call) => call.args['filePath']),
      contains('lib/staged.dart'),
    );
  });

  testWidgets('rename file actions include source and destination paths', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            oldPath: 'lib/old.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.renamed,
          ),
          GitChangeEntry(
            path: 'lib/dirty_new.dart',
            oldPath: 'lib/dirty_old.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.renamed,
          ),
          GitChangeEntry(
            path: 'lib/staged_new.dart',
            oldPath: 'lib/staged_old.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.renamed,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stage').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unstage').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Discard').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();

    expect(
      backend.calls
          .where((call) => call.method == 'stage')
          .map((call) => call.args['filePath']),
      containsAllInOrder(<String>['lib/old.dart', 'lib/new.dart']),
    );
    expect(
      backend.calls
          .where((call) => call.method == 'unstage')
          .map((call) => call.args['filePath']),
      containsAllInOrder(<String>[
        'lib/staged_old.dart',
        'lib/staged_new.dart',
      ]),
    );
    expect(
      backend.calls
          .where((call) => call.method == 'discard')
          .map((call) => call.args['filePath']),
      containsAllInOrder(<String>['lib/old.dart', 'lib/new.dart']),
    );
  });

  testWidgets('discard requires confirmation before backend call', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/changed.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Discard').first);
    await tester.pumpAndSettle();
    expect(backend.calls.where((call) => call.method == 'discard'), isEmpty);

    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'discard').single.args,
      <String, Object?>{'path': '/tmp/project', 'filePath': 'lib/changed.dart'},
    );
  });

  testWidgets('failed source control actions keep current changes visible', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..pushError = const GitCliException('rejected push')
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(find.text('lib/foo.dart'), findsOneWidget);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('refresh stays available after initial load failure', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..statusError = const GitInternalException('index locked');

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.text('index locked'), findsOneWidget);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsOneWidget);

    backend.statusError = null;
    backend.gitStatusResult = const GitStatusResult(
      entries: <GitChangeEntry>[],
    );
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('No changes'), findsOneWidget);
    expect(
      backend.calls.where((call) => call.method == 'status').length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('stash is disabled for untracked-only changes', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stash'));
    await tester.pumpAndSettle();

    expect(backend.calls.where((call) => call.method == 'stash'), isEmpty);
  });

  testWidgets('commit uses message and staged entries only', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'commit staged file');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'commit').single.args,
      <String, Object?>{
        'path': '/tmp/project',
        'message': 'commit staged file',
      },
    );
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.controller.text, isEmpty);
  });

  testWidgets('failed commit keeps the typed message', (tester) async {
    final backend = FakeGitBackend()
      ..commitError = const GitInternalException('index locked')
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'commit that fails');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'commit').single.args,
      <String, Object?>{'path': '/tmp/project', 'message': 'commit that fails'},
    );
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.controller.text, 'commit that fails');
  });

  testWidgets('commit message clears when workspace path changes', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(
      tester,
      backend: backend,
      workspace: _workspace(id: 'workspace-a', path: '/tmp/project-a'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'message for workspace a');
    await tester.pumpAndSettle();
    expect(find.text('message for workspace a'), findsOneWidget);

    await _pumpPanel(
      tester,
      backend: backend,
      workspace: _workspace(id: 'workspace-b', path: '/tmp/project-b'),
    );
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.controller.text, isEmpty);
    final commitButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Commit'),
    );
    expect(commitButton.onPressed, isNull);
  });

  test('sync without upstream fails before pull or push', () async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(branch: 'feature');
    final container = ProviderContainer(
      overrides: [gitBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);
    final provider = workspaceSourceControlControllerProvider('/tmp/project');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);

    await expectLater(
      container.read(provider.notifier).sync(),
      throwsA(isA<NoUpstreamException>()),
    );

    expect(backend.calls.where((call) => call.method == 'pull'), isEmpty);
    expect(backend.calls.where((call) => call.method == 'push'), isEmpty);
  });

  testWidgets(
    'sync is disabled without upstream while push remains available',
    (tester) async {
      final backend = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature',
        );

      await _pumpPanel(tester, backend: backend);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      expect(backend.calls.where((call) => call.method == 'pull'), isEmpty);
      expect(backend.calls.where((call) => call.method == 'push'), isEmpty);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(backend.calls.where((call) => call.method == 'push'), isNotEmpty);
    },
  );

  testWidgets('stash pop opens selector and pops selected stash', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(entries: <GitChangeEntry>[])
      ..gitStashEntries = const <GitStashEntry>[
        GitStashEntry(
          index: 0,
          reference: 'stash@{0}',
          message: 'wip on main',
          oid: 'abc123',
        ),
      ];

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stash pop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stash@{0}'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'stashPop').single.args,
      <String, Object?>{'path': '/tmp/project', 'stashIndex': 0},
    );
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required FakeGitBackend backend,
  Workspace? workspace,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [gitBackendProvider.overrideWithValue(backend)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 520,
            child: WorkspaceGitDiffPanel(
              workspace: workspace ?? _workspace(),
              viewMode: GitDiffViewMode.flat,
              onViewModeChanged: (_) {},
              onOpenGitDiff: ({area, relativePath, required scope}) async {},
            ),
          ),
        ),
      ),
    ),
  );
}

Workspace _workspace({
  String id = 'workspace-1',
  String path = '/tmp/project',
}) {
  final now = DateTime.utc(2026, 6, 6);
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: 'Main',
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

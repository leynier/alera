import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';
import '../unit/fake_source_control_watcher.dart';

void main() {
  for (final viewMode in <GitDiffViewMode>[
    GitDiffViewMode.flat,
    GitDiffViewMode.tree,
  ]) {
    testWidgets(
      'expands read-only submodule changes in ${viewMode.name} view',
      (tester) async {
        final backend = FakeGitBackend()
          ..gitStatusResult = const GitStatusResult(
            entries: <GitChangeEntry>[
              GitChangeEntry(
                path: 'modules/sample',
                area: GitChangeArea.unstaged,
                status: GitChangeStatus.modified,
                submodule: GitSubmoduleStatus(
                  commitChanged: false,
                  trackedChanges: true,
                  untrackedChanges: true,
                  inspectable: true,
                ),
              ),
            ],
          )
          ..gitSubmoduleStatusResult = const GitStatusResult(
            entries: <GitChangeEntry>[
              GitChangeEntry(
                path: 'README.md',
                area: GitChangeArea.unstaged,
                status: GitChangeStatus.modified,
              ),
              GitChangeEntry(
                path: 'new.txt',
                area: GitChangeArea.untracked,
                status: GitChangeStatus.untracked,
              ),
            ],
          );
        String? openedPath;

        await _pumpPanel(
          tester,
          backend: backend,
          viewMode: viewMode,
          onOpenGitDiff:
              ({area, relativePath, gitDiffRoot, required scope}) async {
                openedPath = relativePath;
              },
        );
        await tester.pumpAndSettle();

        expect(find.text('modules/sample/README.md'), findsNothing);
        expect(
          backend.calls.where((call) => call.method == 'submoduleStatus'),
          isEmpty,
        );

        await tester.tap(
          find.text(
            viewMode == GitDiffViewMode.flat ? 'modules/sample' : 'sample',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Inside'), findsOneWidget);
        expect(find.text('modules/sample/README.md'), findsOneWidget);
        expect(find.text('modules/sample/new.txt'), findsOneWidget);
        expect(
          backend.calls
              .where((call) => call.method == 'submoduleStatus')
              .single
              .args,
          <String, Object?>{
            'path': '/tmp/project',
            'submodulePath': 'modules/sample',
            'area': GitChangeArea.unstaged,
          },
        );
        expect(find.byTooltip('Stage'), findsNothing);
        expect(find.byTooltip('Discard'), findsNothing);

        await tester.tap(find.text('modules/sample/README.md'));
        await tester.pump();
        expect(openedPath, 'modules/sample/README.md');
      },
    );
  }

  testWidgets('keeps gitlink actions available when its commit changed', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'modules/sample',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            submodule: GitSubmoduleStatus(
              commitChanged: true,
              trackedChanges: false,
              untrackedChanges: false,
              inspectable: true,
            ),
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Stage'), findsNWidgets(2));
    expect(find.byTooltip('Discard'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Stage').last);
    await tester.pumpAndSettle();
    expect(
      backend.calls.where((call) => call.method == 'stage').single.args,
      <String, Object?>{'path': '/tmp/project', 'filePath': 'modules/sample'},
    );
  });

  testWidgets('hides discard for a moved submodule with internal changes', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'modules/sample',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            submodule: GitSubmoduleStatus(
              commitChanged: true,
              trackedChanges: true,
              untrackedChanges: false,
              inspectable: true,
            ),
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Stage'), findsNWidgets(2));
    expect(find.byTooltip('Discard'), findsNothing);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required FakeGitBackend backend,
  GitDiffViewMode viewMode = GitDiffViewMode.flat,
  OpenGitDiffTabCallback? onOpenGitDiff,
}) {
  final workspace = _workspace();
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(backend),
        sourceControlWatcherProvider.overrideWithValue(
          FakeSourceControlWatcher(),
        ),
        settingsControllerProvider.overrideWith(
          () => _PanelSettingsController(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            height: 540,
            child: WorkspaceGitDiffPanel(
              workspace: workspace,
              sourceControlScope: WorkspaceSourceControlScope(
                workspaceId: workspace.id,
                workspacePath: workspace.path,
                path: workspace.path,
              ),
              viewMode: viewMode,
              onViewModeChanged: (_) {},
              groupMode: GitDiffGroupMode.byArea,
              onGroupModeChanged: (_) {},
              onOpenGitDiff:
                  onOpenGitDiff ??
                  ({area, relativePath, gitDiffRoot, required scope}) async {},
              onOpenGitCommitDiff:
                  ({
                    relativePath,
                    oldPath,
                    required scope,
                    gitDiffRoot,
                    required commitOid,
                    parentOid,
                    required compareRef,
                    subject,
                    message,
                  }) async {},
            ),
          ),
        ),
      ),
    ),
  );
}

Workspace _workspace() {
  final now = DateTime.utc(2026, 7, 9);
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

class _PanelSettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

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
  testWidgets('groups are ordered as staged unstaged and untracked', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
          GitChangeEntry(
            path: 'lib/dirty.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
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

    expect(
      tester.getTopLeft(find.text('Staged')).dy,
      lessThan(tester.getTopLeft(find.text('Unstaged')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Unstaged')).dy,
      lessThan(tester.getTopLeft(find.text('Untracked')).dy),
    );
  });

  testWidgets(
    'unified group mode shows one changes section with area markers',
    (tester) async {
      final backend = FakeGitBackend()
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/new.dart',
              area: GitChangeArea.untracked,
              status: GitChangeStatus.untracked,
            ),
            GitChangeEntry(
              path: 'lib/dirty.dart',
              area: GitChangeArea.unstaged,
              status: GitChangeStatus.modified,
            ),
            GitChangeEntry(
              path: 'lib/staged.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
            ),
            GitChangeEntry(
              path: 'lib/dirty.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
            ),
          ],
        );

      await _pumpPanel(
        tester,
        backend: backend,
        groupMode: GitDiffGroupMode.unified,
      );
      await tester.pumpAndSettle();

      expect(find.text('Changes'), findsOneWidget);
      expect(find.text('Staged'), findsNothing);
      expect(find.text('Unstaged'), findsNothing);
      expect(find.text('Untracked'), findsNothing);
      expect(find.text('lib/new.dart'), findsOneWidget);
      expect(find.text('lib/staged.dart'), findsOneWidget);
      // Same path appears once staged and once unstaged.
      expect(find.text('lib/dirty.dart'), findsNWidgets(2));
      expect(find.text('S'), findsNWidgets(2));
    },
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required FakeGitBackend backend,
  GitDiffGroupMode groupMode = GitDiffGroupMode.byArea,
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
          () => _PanelSettingsController(AleraSettings.defaults),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 520,
            child: WorkspaceGitDiffPanel(
              workspace: workspace,
              sourceControlScope: WorkspaceSourceControlScope(
                workspaceId: workspace.id,
                workspacePath: workspace.path,
                path: workspace.path,
              ),
              viewMode: GitDiffViewMode.flat,
              onViewModeChanged: (_) {},
              groupMode: groupMode,
              onGroupModeChanged: (_) {},
              onOpenGitDiff:
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

class _PanelSettingsController extends SettingsController {
  _PanelSettingsController(this._settings);

  final AleraSettings _settings;

  @override
  AleraSettings build() => _settings;
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

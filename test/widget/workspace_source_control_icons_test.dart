import 'package:alera/src/design_system/icons/alera_icons.dart';
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
  testWidgets('source control actions use VS Code Codicons', (tester) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
        ahead: 1,
        behind: 1,
      )
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
      )
      ..gitStashEntries = const <GitStashEntry>[
        GitStashEntry(
          index: 0,
          reference: 'stash@{0}',
          message: 'wip on main',
          oid: 'abc123',
        ),
      ];

    await _pumpPanel(tester, backend);
    await tester.pumpAndSettle();

    expect(find.byIcon(AleraIcons.gitStage), findsWidgets);
    expect(find.byIcon(AleraIcons.gitUnstage), findsWidgets);

    final discardAction = find.byTooltip('Discard').last;
    expect(
      find.descendant(
        of: discardAction,
        matching: find.byIcon(AleraIcons.gitDiscard),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: discardAction,
        matching: find.byIcon(AleraIcons.close),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Source Control Actions'));
    await tester.pumpAndSettle();

    for (final icon in <IconData>[
      AleraIcons.gitCommit,
      AleraIcons.gitSync,
      AleraIcons.gitStage,
      AleraIcons.gitUnstage,
      AleraIcons.gitDiscard,
      AleraIcons.gitFetch,
      AleraIcons.gitPull,
      AleraIcons.gitPush,
      AleraIcons.gitPublish,
      AleraIcons.gitStash,
      AleraIcons.gitStashPop,
    ]) {
      expect(find.byIcon(icon), findsWidgets);
    }
  });
}

Future<void> _pumpPanel(WidgetTester tester, FakeGitBackend backend) {
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
  @override
  AleraSettings build() => AleraSettings.defaults;
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

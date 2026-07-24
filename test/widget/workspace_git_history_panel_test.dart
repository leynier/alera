import 'package:alera/src/design_system/surfaces/hover_container.dart';
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
  testWidgets('commit rows truncate ref badges instead of overflowing', (
    tester,
  ) async {
    final backend = _multiRefBackend();

    await _pumpPanel(tester, backend: backend, width: 420, height: 520);
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMMITS'));
    await tester.pumpAndSettle();

    expect(find.text('Add Feature'), findsOneWidget);
    expect(find.text('feat/settings-fullscreen-modal'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('narrow commit rows collapse ref badges into the hidden count', (
    tester,
  ) async {
    final backend = _multiRefBackend();

    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpPanel(tester, backend: backend, width: 200, height: 700);
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMMITS'));
    await tester.pumpAndSettle();

    expect(find.text('Add Feature'), findsOneWidget);
    expect(find.text('feat/settings-fullscreen-modal'), findsNothing);
    expect(find.text('+4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('commits header toggles from anywhere except its actions', (
    tester,
  ) async {
    final backend = _multiRefBackend();

    await _pumpPanel(tester, backend: backend, width: 420, height: 520);
    await tester.pumpAndSettle();

    final header = tester.getRect(find.byType(HoverContainer));
    final refresh = tester.getRect(find.byTooltip('Refresh Commits'));

    // Empty space between the label and the refresh action still expands.
    await tester.tapAt(Offset(refresh.left - 8, header.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('Add Feature'), findsOneWidget);

    // The refresh action reloads instead of collapsing the section again.
    await tester.tap(find.byTooltip('Refresh Commits'));
    await tester.pumpAndSettle();
    expect(find.text('Add Feature'), findsOneWidget);
    expect(backend.calls.where((call) => call.method == 'history').length, 2);
  });
}

FakeGitBackend _multiRefBackend() {
  return FakeGitBackend()
    ..gitRepositoryStateResult = const GitRepositoryState(
      branch: 'feat/settings-fullscreen-modal',
      upstream: 'origin/feat/settings-fullscreen-modal',
    )
    ..gitHistoryResult = GitHistoryResult(
      currentRef: const GitHistoryItemRef(
        id: 'refs/heads/feat/settings-fullscreen-modal',
        name: 'feat/settings-fullscreen-modal',
        revision: 'abc123456789',
      ),
      hasIncomingChanges: false,
      hasOutgoingChanges: false,
      hasMore: false,
      limit: 50,
      items: <GitHistoryItem>[
        GitHistoryItem(
          id: 'abc123456789',
          parentIds: const <String>[],
          subject: 'Add Feature',
          message: 'Add Feature',
          references: const <GitHistoryItemRef>[
            GitHistoryItemRef(
              id: 'refs/heads/feat/settings-fullscreen-modal',
              name: 'feat/settings-fullscreen-modal',
              revision: 'abc123456789',
            ),
            GitHistoryItemRef(
              id: 'refs/heads/main',
              name: 'main',
              revision: 'abc123456789',
            ),
            GitHistoryItemRef(
              id: 'refs/remotes/origin/main',
              name: 'origin/main',
              revision: 'abc123456789',
            ),
            GitHistoryItemRef(
              id: 'refs/tags/v0.14.0',
              name: 'v0.14.0',
              revision: 'abc123456789',
            ),
          ],
        ),
      ],
    );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required FakeGitBackend backend,
  required double width,
  required double height,
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
            width: width,
            height: height,
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

class _PanelSettingsController extends SettingsController {
  _PanelSettingsController(this._settings);

  final AleraSettings _settings;

  @override
  AleraSettings build() => _settings;
}

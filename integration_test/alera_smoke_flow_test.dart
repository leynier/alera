import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/app.dart';
import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/infra/drift_project_config_repository.dart';
import 'package:alera/src/features/projects/infra/drift_project_repository.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/settings/infra/drift_settings_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_repository.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';

import 'e2e_git_backend.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adds a local folder and opens its terminal workspace', (
    tester,
  ) async {
    final tempRoot = await Directory.systemTemp.createTemp('alera-e2e-');
    addTearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });
    // Short unique name: avoids collisions with leftover runtime-host projects
    // from prior local runs, without overflowing the explorer path toolbar.
    final projectName = 'e2e-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final projectDir = Directory(p.join(tempRoot.path, projectName))
      ..createSync(recursive: true);

    final db = AleraDatabase(executor: NativeDatabase.memory());
    var dbClosed = false;
    Future<void> closeDb() async {
      if (dbClosed) {
        return;
      }
      dbClosed = true;
      await db.close();
    }

    addTearDown(closeDb);

    final terminalRuntime = _E2eTerminalRuntime();
    addTearDown(terminalRuntime.dispose);

    // Keep the smoke flow on Drift-backed repositories so CI does not need a
    // live terminal-host process for project/workspace persistence. The product
    // path still exercises the real workbench UI and dialogs; only the host IPC
    // boundary is replaced.
    final projectRepository = DriftProjectRepository(db);
    final workbenchRepository = DriftWorkbenchRepository(db);
    final projectConfigRepository = DriftProjectConfigRepository(db);
    final settingsRepository = DriftSettingsRepository(db);
    const gitBackend = E2eGitBackend();
    final projectsService = ProjectsService(
      projectService: ProjectService(gitBackend),
      projectRepository: projectRepository,
      removeProjectConfigOverride: projectConfigRepository.remove,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith((ref) async {
            ref.onDispose(closeDb);
            return db;
          }),
          projectRepositoryProvider.overrideWithValue(projectRepository),
          projectsServiceProvider.overrideWithValue(projectsService),
          workbenchRepositoryProvider.overrideWithValue(workbenchRepository),
          projectConfigRepositoryProvider.overrideWithValue(
            projectConfigRepository,
          ),
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          managedWorkspaceRuntimeProvider.overrideWithValue(null),
          gitBackendProvider.overrideWithValue(gitBackend),
          terminalRuntimeProvider.overrideWith((ref) => terminalRuntime),
        ],
        child: const AleraApp(),
      ),
    );

    await _pumpUntilFound(tester, find.text('No projects yet'));

    await tester.tap(find.text('Add Project').last);
    await _pumpUntilFound(tester, find.byType(AddProjectDialog));

    final projectPathField = find.descendant(
      of: find.byType(AddProjectDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(projectPathField.first, projectDir.path);
    await tester.pump();

    final submitButton = find.descendant(
      of: find.byType(AddProjectDialog),
      matching: find.widgetWithText(FilledButton, 'Add Project'),
    );
    await tester.tap(submitButton);

    final workspace = await _pumpUntilWorkspaceCreated(
      tester,
      projectRepository: projectRepository,
      workbenchRepository: workbenchRepository,
      workspacePath: projectDir.path,
    );
    final workspaceRow = find.byKey(
      ValueKey<String>('workspace-row:regular:${workspace.id}'),
    );
    await _pumpUntilFound(tester, workspaceRow);
    await tester.ensureVisible(workspaceRow);
    await tester.pumpAndSettle();
    await tester.tap(workspaceRow);
    await _pumpUntilFound(tester, find.byTooltip('New Tab'));
    await _pumpUntilFound(tester, find.text('E2E terminal: Terminal 1'));

    await tester.tap(find.byTooltip('New Tab').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Terminal'));
    await _pumpUntilFound(tester, find.text('E2E terminal: Terminal 2'));

    expect(
      terminalRuntime.startedTitles,
      containsAll(<String>['Terminal 1', 'Terminal 2']),
    );
  });
}

Future<Workspace> _pumpUntilWorkspaceCreated(
  WidgetTester tester, {
  required DriftProjectRepository projectRepository,
  required DriftWorkbenchRepository workbenchRepository,
  required String workspacePath,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final projects = await projectRepository.listAll();
    for (final project in projects) {
      final workspaces = await workbenchRepository.listWorkspaces(project.id);
      for (final workspace in workspaces) {
        if (workspace.path == workspacePath) {
          return workspace;
        }
      }
    }
  }
  fail('Expected workspace to be persisted for path: $workspacePath');
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 200,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.any(finder)) {
      return;
    }
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .take(40)
      .join(' | ');
  fail('Expected to find $finder. Visible text: $visibleText');
}

class _E2eTerminalRuntime implements TerminalRuntime {
  final Map<String, _E2eTerminalSessionHandle> _sessions =
      <String, _E2eTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  Iterable<String> get startedTitles => _sessions.values
      .where((session) => session.isRunning)
      .map((session) => session.displayTitle);

  @override
  TerminalSessionHandle? peekSession(String tabId) => _sessions[tabId];

  @override
  void setActiveWorkspace(String? workspaceId) {}

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions.putIfAbsent(
      tab.id,
      () => _E2eTerminalSessionHandle(workspace: workspace, tab: tab),
    );
  }

  @override
  void closeTab(String tabId) {
    _sessions.remove(tabId)?.dispose();
  }

  @override
  void closeWorkspace(String workspaceId) {
    final tabIds = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in tabIds) {
      closeTab(tabId);
    }
  }

  @override
  void releaseTab(String tabId) => closeTab(tabId);

  @override
  void releaseWorkspace(String workspaceId) => closeWorkspace(workspaceId);

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    unawaited(_exitController.close());
  }
}

class _E2eTerminalSessionHandle extends TerminalSessionHandle {
  _E2eTerminalSessionHandle({required this.workspace, required this.tab});

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  bool _started = false;

  @override
  String get displayTitle => tab.title;

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

  @override
  String? get errorMessage => null;

  @override
  bool get isRunning => _started;

  @override
  bool get isStarting => false;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return Center(key: key, child: Text('E2E terminal: ${tab.title}'));
  }

  @override
  Future<void> ensureStarted() async {
    if (_started) {
      return;
    }
    _started = true;
    notifyListeners();
  }

  @override
  void requestFocus() {}

  @override
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

  @override
  Future<void> restart() => ensureStarted();
}

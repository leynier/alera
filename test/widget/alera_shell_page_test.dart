import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  Future<Database> openMemoryDb() {
    return databaseFactoryMemory.openDatabase('test.db');
  }

  Future<_ShellPumpHarness> pumpShell(
    WidgetTester tester, {
    required WorkbenchState state,
    _FakeTerminalRuntime? terminalRuntime,
    WorkspaceFolderOpener? workspaceFolderOpener,
  }) async {
    final controller = _ShellTestWorkbenchController(state);
    final runtime = terminalRuntime ?? _FakeTerminalRuntime();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => await openMemoryDb(),
          ),
          workbenchControllerProvider.overrideWith((ref) => controller),
          terminalRuntimeProvider.overrideWith((ref) => runtime),
          if (workspaceFolderOpener != null)
            workspaceFolderOpenerProvider.overrideWith(
              (ref) => workspaceFolderOpener,
            ),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return _ShellPumpHarness(controller: controller, runtime: runtime);
  }

  testWidgets('shell renders the terminal workbench for the active workspace', (
    tester,
  ) async {
    await pumpShell(tester, state: _populatedWorkbenchState());

    expect(find.byTooltip('New terminal'), findsOneWidget);
    expect(find.text('New terminal'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(find.text('No workspace selected'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'WorkbenchStatusBar',
      ),
      findsNothing,
    );
    expect(find.text('/repo/alera'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Add project'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('shell renders split terminal panes for one workspace', (
    tester,
  ) async {
    await pumpShell(tester, state: _splitWorkbenchState());

    expect(find.byTooltip('New terminal'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsOneWidget,
    );
  });

  testWidgets('dragging a tab to a pane edge creates a directional split', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpShell(tester, state: _stackedWorkbenchState());

    final tabs = find.byWidgetPredicate((widget) => widget is Draggable);
    expect(tabs, findsNWidgets(2));
    expect(find.byTooltip('New terminal'), findsOneWidget);

    final secondTabStart = tester.getTopLeft(tabs.at(1)) + const Offset(24, 20);
    final terminalRect = tester.getRect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
    );
    final target = Offset(terminalRect.right - 48, terminalRect.center.dy);
    final gesture = await tester.startGesture(secondTabStart);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 96));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byTooltip('New terminal'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsOneWidget,
    );
  });

  testWidgets('shell shows the empty state when there are no projects', (
    tester,
  ) async {
    await pumpShell(tester, state: const WorkbenchState(bootstrapped: true));

    expect(find.text('No projects yet'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(FilledButton, 'Add project'), findsOneWidget);
  });

  testWidgets('shell shows the empty state when no workspace is selected', (
    tester,
  ) async {
    await pumpShell(
      tester,
      state: _populatedWorkbenchState().copyWith(clearActiveWorkspaceId: true),
    );

    expect(find.text('No workspace selected'), findsOneWidget);
    expect(
      find.text(
        'Select a workspace from the sidebar to open its terminal tabs.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('New terminal'), findsNothing);
  });

  testWidgets('terminal exit closes its tab and activates the remaining tab', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _stackedWorkbenchState());

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-2');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(
      harness.controller.state.tabsFor('workspace-1').map((tab) => tab.id),
      <String>['tab-1'],
    );
    expect(harness.controller.state.activeWorkspaceId, 'workspace-1');
    expect(harness.controller.state.activeWorkspaceTab?.id, 'tab-1');
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
  });

  testWidgets('terminal exit closes the last tab and deselects the workspace', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-1');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-1']);
    expect(harness.controller.state.tabsFor('workspace-1'), isEmpty);
    expect(harness.controller.state.activeWorkspace, isNull);
    expect(find.text('No workspace selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsNothing,
    );
  });

  testWidgets('terminal exit closes tabs even when no workspace is selected', (
    tester,
  ) async {
    final harness = await pumpShell(
      tester,
      state: _populatedWorkbenchState().copyWith(clearActiveWorkspaceId: true),
    );

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-1');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-1']);
    expect(harness.controller.state.tabsFor('workspace-1'), isEmpty);
    expect(harness.controller.state.activeWorkspace, isNull);
    expect(find.text('No workspace selected'), findsOneWidget);
  });

  testWidgets('workspace context menu shows supported workspace actions', (
    tester,
  ) async {
    final opener = WorkspaceFolderOpener(
      processRunner: _NoopProcessRunner(),
      platform: WorkspaceFolderPlatform.macos,
      directoryExists: (_) async => true,
    );
    await pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      workspaceFolderOpener: opener,
    );

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Open in Finder'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Remove workspace?'), findsNothing);
  });

  testWidgets('workspace context menu sleep closes live sessions only', (
    tester,
  ) async {
    final runtime = _FakeTerminalRuntime();
    await pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      terminalRuntime: runtime,
      workspaceFolderOpener: WorkspaceFolderOpener(
        processRunner: _NoopProcessRunner(),
        platform: WorkspaceFolderPlatform.macos,
        directoryExists: (_) async => true,
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();

    expect(runtime.closedWorkspaceIds, <String>['workspace-1']);
    expect(find.text('Terminal 1'), findsAtLeastNWidgets(1));
  });
}

WorkbenchState _stackedWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final firstTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  final secondTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: workspace.id,
    title: 'Terminal 2',
    createdAt: now,
    updatedAt: now,
  );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[firstTab, secondTab],
    },
    layoutByWorkspace: <String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[firstTab.id, secondTab.id],
      ),
    },
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: secondTab.id},
    bootstrapped: true,
  );
}

WorkbenchState _populatedWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final tab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[tab],
    },
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: tab.id},
    layoutByWorkspace: <String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[tab.id],
      ),
    },
    bootstrapped: true,
  );
}

WorkbenchState _splitWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final firstTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  final secondTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: workspace.id,
    title: 'Terminal 2',
    createdAt: now,
    updatedAt: now,
  );
  final layout =
      WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[firstTab.id],
      ).splitWithGroup(
        targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
        zone: WorkbenchDropZone.right,
        newGroup: WorkbenchPaneGroup(
          id: 'group-2',
          tabIds: <String>[secondTab.id],
          activeTabId: secondTab.id,
        ),
      );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[firstTab, secondTab],
    },
    layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: layout},
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: secondTab.id},
    bootstrapped: true,
  );
}

class _ShellTestWorkbenchController extends WorkbenchController {
  _ShellTestWorkbenchController(this._bootstrapState)
    : super(
        projectsService: ProjectsService(
          projectService: ProjectService(_NoopProcessRunner()),
          projectRepository: _NoopProjectRepository(),
        ),
        repository: _NoopWorkbenchRepository(),
        workspaceService: WorkspaceService(
          repository: _NoopWorkbenchRepository(),
          projectService: ProjectService(_NoopProcessRunner()),
          processRunner: _NoopProcessRunner(),
        ),
        workspaceTabService: WorkspaceTabService(
          repository: _NoopWorkbenchRepository(),
        ),
      );

  final WorkbenchState _bootstrapState;

  @override
  Future<void> bootstrap() async {
    state = _bootstrapState;
  }
}

class _ShellPumpHarness {
  const _ShellPumpHarness({required this.controller, required this.runtime});

  final _ShellTestWorkbenchController controller;
  final _FakeTerminalRuntime runtime;
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> closedWorkspaceIds = <String>[];
  final List<String> closedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions.putIfAbsent(
      tab.id,
      () => _FakeTerminalSessionHandle(workspace: workspace, tab: tab),
    );
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
    _sessions.remove(tabId)?.dispose();
  }

  void emitExit({
    required String workspaceId,
    required String tabId,
    int exitCode = 0,
  }) {
    _exitController.add(
      TerminalRuntimeExitEvent(
        workspaceId: workspaceId,
        tabId: tabId,
        exitCode: exitCode,
      ),
    );
  }

  @override
  void closeWorkspace(String workspaceId) {
    closedWorkspaceIds.add(workspaceId);
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      _sessions.remove(tabId)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    unawaited(_exitController.close());
  }
}

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({required this.workspace, required this.tab});

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  bool _started = false;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  String get displayTitle => tab.title;

  @override
  bool get isRunning => _started;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {
    _started = true;
  }

  @override
  Future<void> restart() => ensureStarted();

  @override
  Widget buildView({Key? key, bool autofocus = false}) {
    return Center(
      key: ValueKey<String>('fake-terminal-${tab.id}'),
      child: Text('Terminal ${tab.title}'),
    );
  }

  @override
  void requestFocus() {}
}

class _NoopWorkbenchRepository implements WorkbenchRepository {
  final Map<String, WorkbenchLayout> layouts = <String, WorkbenchLayout>{};

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async => null;

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async => null;

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    return layouts[workspaceId];
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(
    String workspaceId,
  ) async => const <WorkspaceTabRecord>[];

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async =>
      const <Workspace>[];

  @override
  Future<void> removeWorkspaceTab(String tabId) async {}

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {}

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {}

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {}

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    layouts.remove(workspaceId);
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async =>
      tab;

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    layouts[layout.workspaceId] = layout;
    return layout;
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async => workspace;

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) =>
      const Stream<List<WorkspaceTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}

class _NoopProjectRepository implements ProjectRepository {
  @override
  Future<Project> add(Project project) async => project;

  @override
  Future<List<Project>> listAll() async => const <Project>[];

  @override
  Future<void> remove(String projectId) async {}

  @override
  Future<Project> update(Project project) async => project;

  @override
  Stream<List<Project>> watchAll() => const Stream<List<Project>>.empty();
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

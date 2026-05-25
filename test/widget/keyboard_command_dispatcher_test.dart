import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('split command stays safe after the dispatcher host unmounts', (
    tester,
  ) async {
    final workspace = _workspace();
    final initialTab = _tab(id: 'tab-1');
    final splitTab = _tab(id: 'tab-2');
    final controller = _DispatcherTestWorkbenchController(
      seed: WorkbenchState(
        workspacesByProject: <String, List<Workspace>>{
          workspace.projectId: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[initialTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{
          workspace.id: WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[initialTab.id],
          ),
        },
        activeWorkspaceId: workspace.id,
      ),
    );
    final runtime = _FakeTerminalRuntime();
    final container = ProviderContainer(
      overrides: [
        workbenchControllerProvider.overrideWith((ref) => controller),
        terminalRuntimeProvider.overrideWith((ref) => runtime),
      ],
    );
    addTearDown(container.dispose);

    final showHost = ValueNotifier<bool>(true);
    addTearDown(showHost.dispose);

    late WidgetRef dispatcherRef;
    late BuildContext dispatcherContext;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: showHost,
            builder: (context, visible, _) {
              if (!visible) {
                return const SizedBox.shrink();
              }
              return Consumer(
                builder: (context, ref, _) {
                  dispatcherRef = ref;
                  dispatcherContext = context;
                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
      ),
    );

    KeyboardCommandDispatcher(
      ref: dispatcherRef,
      context: dispatcherContext,
    ).dispatch(KeyboardActionId.splitRight);

    showHost.value = false;
    await tester.pump();

    controller.completeSplit(splitTab);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(runtime.focusedTabIds, contains(splitTab.id));
  });
}

Workspace _workspace() {
  return Workspace(
    id: 'ws-1',
    projectId: 'project-1',
    name: 'Main',
    branch: 'main',
    path: '/tmp/alera',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab({required String id}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: 'ws-1',
    title: 'Terminal',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _DispatcherTestWorkbenchController extends WorkbenchController {
  _DispatcherTestWorkbenchController({required WorkbenchState seed})
    : _splitCompleter = Completer<WorkspaceTabRecord>(),
      super(
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
      ) {
    state = seed;
  }

  final Completer<WorkspaceTabRecord> _splitCompleter;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) {
    return _splitCompleter.future;
  }

  void completeSplit(WorkspaceTabRecord tab) {
    if (_splitCompleter.isCompleted) {
      return;
    }
    _splitCompleter.complete(tab);
  }
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  Iterable<String> get focusedTabIds => _sessions.entries
      .where((entry) => entry.value.requestFocusCalls > 0)
      .map((entry) => entry.key);

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
    _sessions.remove(tabId)?.dispose();
  }

  @override
  void closeWorkspace(String workspaceId) {
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
  int requestFocusCalls = 0;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  String get displayTitle => tab.title;

  @override
  bool get isRunning => true;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> restart() async {}

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return const SizedBox.shrink();
  }

  @override
  void requestFocus() {
    requestFocusCalls += 1;
  }
}

class _NoopWorkbenchRepository implements WorkbenchRepository {
  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async => null;

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async => null;

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async =>
      null;

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
  Future<void> removeWorkbenchLayout(String workspaceId) async {}

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async =>
      tab;

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async =>
      layout;

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

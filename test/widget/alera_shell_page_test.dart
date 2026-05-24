import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/application/chat_repository.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/application/worktree_service.dart';
import 'package:alera/src/features/projects/domain/chat_message.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/shell/presentation/alera_top_bar.dart';
import 'package:alera/src/features/workbench/application/terminal_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/workbench_status_bar.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  Future<Database> openMemoryDb() {
    return databaseFactoryMemory.openDatabase('test.db');
  }

  Future<void> pumpShell(
    WidgetTester tester, {
    required WorkbenchState state,
  }) async {
    final controller = _ShellTestWorkbenchController(state);
    final terminalRuntime = _FakeTerminalRuntime();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => await openMemoryDb(),
          ),
          workbenchControllerProvider.overrideWith((ref) => controller),
          terminalRuntimeProvider.overrideWith((ref) => terminalRuntime),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shell does not render the global top bar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpShell(tester, state: _populatedWorkbenchState());

    expect(find.byType(AleraTopBar), findsNothing);
  });

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
    expect(find.text('Pick a workspace'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(WorkbenchStatusBar),
        matching: find.text('/repo/alera'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shell shows the empty state when no workspace is selected', (
    tester,
  ) async {
    await pumpShell(tester, state: const WorkbenchState(bootstrapped: true));

    expect(find.text('Pick a workspace'), findsOneWidget);
    expect(find.text('Add project'), findsOneWidget);
  });
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
  final tab = TerminalTabRecord(
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
    tabsByWorkspace: <String, List<TerminalTabRecord>>{
      workspace.id: <TerminalTabRecord>[tab],
    },
    expandedProjectIds: <String>{project.id},
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: tab.id},
    bootstrapped: true,
  );
}

class _ShellTestWorkbenchController extends WorkbenchController {
  _ShellTestWorkbenchController(this._bootstrapState)
    : super(
        projectsService: ProjectsService(
          projectService: ProjectService(_NoopProcessRunner()),
          projectRepository: _NoopProjectRepository(),
          chatRepository: _NoopChatRepository(),
          worktreeService: WorktreeService(
            projectRepository: _NoopProjectRepository(),
            processRunner: _NoopProcessRunner(),
          ),
        ),
        repository: _NoopWorkbenchRepository(),
        workspaceService: WorkspaceService(
          repository: _NoopWorkbenchRepository(),
          projectService: ProjectService(_NoopProcessRunner()),
          processRunner: _NoopProcessRunner(),
        ),
        terminalTabService: TerminalTabService(
          repository: _NoopWorkbenchRepository(),
        ),
      );

  final WorkbenchState _bootstrapState;

  @override
  Future<void> bootstrap() async {
    state = _bootstrapState;
  }
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required TerminalTabRecord tab,
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
  }
}

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({required this.workspace, required this.tab});

  final Workspace workspace;
  final TerminalTabRecord tab;
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
}

class _NoopWorkbenchRepository implements WorkbenchRepository {
  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async => null;

  @override
  Future<TerminalTabRecord?> findTerminalTabById(String tabId) async => null;

  @override
  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId) async =>
      const <TerminalTabRecord>[];

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async =>
      const <Workspace>[];

  @override
  Future<void> removeTerminalTab(String tabId) async {}

  @override
  Future<void> removeTerminalTabsForWorkspace(String workspaceId) async {}

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {}

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {}

  @override
  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab) async =>
      tab;

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async => workspace;

  @override
  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId) =>
      const Stream<List<TerminalTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}

class _NoopProjectRepository implements ProjectRepository {
  @override
  Future<Project> add(Project project) async => project;

  @override
  Future<Worktree> addWorktree(Worktree worktree) => throw UnimplementedError();

  @override
  Future<Worktree?> findWorktreeById(String worktreeId) async => null;

  @override
  Future<List<Project>> listAll() async => const <Project>[];

  @override
  Future<List<Worktree>> listWorktrees(String projectId) async =>
      const <Worktree>[];

  @override
  Future<void> remove(String projectId) async {}

  @override
  Future<Project> update(Project project) async => project;

  @override
  Future<Worktree> updateWorktree(Worktree worktree) =>
      throw UnimplementedError();

  @override
  Stream<List<Project>> watchAll() => const Stream<List<Project>>.empty();

  @override
  Stream<List<Worktree>> watchWorktrees(String projectId) =>
      const Stream<List<Worktree>>.empty();
}

class _NoopChatRepository implements ChatRepository {
  @override
  Future<ChatMessage> appendMessage(ChatMessage message) =>
      throw UnimplementedError();

  @override
  Future<ChatSummary?> findById(String chatId) async => null;

  @override
  Future<List<ChatSummary>> listByProject(String projectId) async =>
      const <ChatSummary>[];

  @override
  Future<List<TimelineCell>> loadCells(String chatId) async =>
      const <TimelineCell>[];

  @override
  Future<List<ChatMessage>> loadMessages(String chatId) async =>
      const <ChatMessage>[];

  @override
  Future<int> nextSeq(String chatId) => throw UnimplementedError();

  @override
  Future<void> remove(String chatId, {bool cascadeMessages = true}) async {}

  @override
  Future<void> replaceCells(String chatId, List<TimelineCell> cells) async {}

  @override
  Future<ChatSummary> upsert(ChatSummary chat) => throw UnimplementedError();

  @override
  Stream<List<ChatSummary>> watchByProject(String projectId) =>
      const Stream<List<ChatSummary>>.empty();
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

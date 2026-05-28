part of 'app_providers_test.dart';

Project _project({required String id, required String path}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Project(
    id: id,
    name: 'Alera',
    repoPath: path,
    createdAt: now,
    updatedAt: now,
    kind: ProjectKind.gitRepository,
  );
}

String _slugSegment(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_/]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

Future<HttpClientResponse> _postHook(
  int port, {
  required String path,
  required String token,
  required String body,
}) async {
  final client = HttpClient();
  addTearDown(client.close);
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  request.headers.set(aleraAgentHookTokenHeader, token);
  request.headers.contentType = ContentType.json;
  request.write(body);
  return request.close();
}

class _TestSettingsController extends SettingsController {
  _TestSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;

  void setState(AleraSettings next) {
    state = next;
  }
}

final class _FakeTerminalHostClient implements TerminalHostClient {
  _FakeTerminalHostClient({TerminalHostAttachment? attachment})
    : attachment =
          attachment ??
          TerminalHostAttachment(
            sessionId: 'session-1',
            created: true,
            running: true,
            snapshot: Uint8List(0),
          );

  final TerminalHostAttachment attachment;
  final List<TerminalHostConfig> ensureStartedConfigs = <TerminalHostConfig>[];
  final List<TerminalHostConfig> configureConfigs = <TerminalHostConfig>[];
  final List<GhosttyTerminalShellLaunch> launches =
      <GhosttyTerminalShellLaunch>[];

  @override
  Stream<TerminalHostEvent> get events =>
      const Stream<TerminalHostEvent>.empty();

  @override
  Future<void> configure(TerminalHostConfig config) async {
    configureConfigs.add(config);
  }

  @override
  Future<TerminalHostAttachment> createOrAttach({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    launches.add(launch);
    return TerminalHostAttachment(
      sessionId: sessionId,
      created: attachment.created,
      running: attachment.running,
      snapshot: attachment.snapshot,
      exitCode: attachment.exitCode,
    );
  }

  @override
  Future<void> detach(String sessionId) async {}

  @override
  void dispose() {}

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) async {
    ensureStartedConfigs.add(config);
  }

  @override
  Future<void> resize({
    required String sessionId,
    required int cols,
    required int rows,
  }) async {}

  @override
  Future<void> terminate(String sessionId) async {}

  @override
  Future<void> write({
    required String sessionId,
    required List<int> bytes,
  }) async {}
}

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final List<Workspace> workspaces = <Workspace>[];
  final List<WorkspaceTabRecord> tabs = <WorkspaceTabRecord>[];
  final Map<String, WorkbenchLayout> layouts = <String, WorkbenchLayout>{};

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    for (final workspace in workspaces) {
      if (workspace.id == workspaceId) {
        return workspace;
      }
    }
    return null;
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    for (final tab in tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    return layouts[workspaceId];
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    return tabs
        .where((tab) => tab.workspaceId == workspaceId)
        .toList(growable: false);
  }

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    return workspaces
        .where((workspace) => workspace.projectId == projectId)
        .toList(growable: false);
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    tabs.removeWhere((tab) => tab.id == tabId);
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    tabs.removeWhere((tab) => tab.workspaceId == workspaceId);
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    workspaces.removeWhere((workspace) => workspace.id == workspaceId);
    if (cascadeTabs) {
      await removeWorkspaceTabsForWorkspace(workspaceId);
    }
    await removeWorkbenchLayout(workspaceId);
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    final removed = workspaces
        .where((workspace) => workspace.projectId == projectId)
        .toList(growable: false);
    workspaces.removeWhere((workspace) => workspace.projectId == projectId);
    for (final workspace in removed) {
      await removeWorkbenchLayout(workspace.id);
    }
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    layouts.remove(workspaceId);
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    final index = tabs.indexWhere((entry) => entry.id == tab.id);
    if (index == -1) {
      tabs.add(tab);
    } else {
      tabs[index] = tab;
    }
    return tab;
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    layouts[layout.workspaceId] = layout;
    return layout;
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    final index = workspaces.indexWhere((entry) => entry.id == workspace.id);
    if (index == -1) {
      workspaces.add(workspace);
    } else {
      workspaces[index] = workspace;
    }
    return workspace;
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) {
    return const Stream<List<WorkspaceTabRecord>>.empty();
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) {
    return const Stream<List<Workspace>>.empty();
  }
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];
  List<String> sourceBranches = <String>['main'];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(
      _ProcessCall(
        executable: executable,
        arguments: List<String>.from(arguments),
        workingDirectory: workingDirectory,
      ),
    );

    if (arguments.contains('for-each-ref')) {
      return ProcessRunOutput(
        exitCode: 0,
        stdout: '${sourceBranches.join('\n')}\n',
        stderr: '',
      );
    }
    if (arguments.length >= 2 &&
        arguments[0] == 'check-ref-format' &&
        arguments[1] == '--branch') {
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }
    if (arguments.length >= 4 &&
        arguments[0] == 'rev-parse' &&
        arguments[1] == '--verify' &&
        arguments[2] == '--quiet') {
      return const ProcessRunOutput(exitCode: 1, stdout: '', stderr: '');
    }
    if (arguments.length >= 5 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'add') {
      Directory(arguments[4]).createSync(recursive: true);
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

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

class _ProcessCall {
  const _ProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  @override
  Future<void> open(Uri uri) async {}
}

class _FakeNotificationPresenter implements AgentStatusNotificationPresenter {
  int initializeCalls = 0;
  final List<AgentStatusNotification> notifications =
      <AgentStatusNotification>[];
  AgentStatusNotificationSelectionHandler? onSelected;

  @override
  Future<void> initialize({
    required AgentStatusNotificationSelectionHandler onSelected,
  }) async {
    initializeCalls++;
    this.onSelected = onSelected;
  }

  @override
  Future<void> show(AgentStatusNotification notification) async {
    notifications.add(notification);
  }
}

class _FakeNotificationWindowActivator
    implements AgentNotificationWindowActivator {
  int calls = 0;

  @override
  Future<void> showAndFocus() async {
    calls++;
  }
}

class _FakeStatusSink implements AgentStatusSink {
  final List<AgentHookEvent> events = <AgentHookEvent>[];

  @override
  void applyHookEvent(AgentHookEvent event) {
    events.add(event);
  }
}

class _TestWorkbenchController extends WorkbenchController {
  _TestWorkbenchController(this._seed);

  final WorkbenchState _seed;
  final List<String> selectedWorkspaceIds = <String>[];
  final Map<String, String> activeTabs = <String, String>{};

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    selectedWorkspaceIds.add(workspace.id);
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
    );
  }

  @override
  void setActiveTab({required String workspaceId, required String tabId}) {
    activeTabs[workspaceId] = tabId;
    state = state.copyWith(
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspaceId: tabId,
      },
    );
  }
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final StreamController<TerminalRuntimeExitEvent> _events =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> closedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _events.stream;

  void emitExit(TerminalRuntimeExitEvent event) {
    _events.add(event);
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
  }

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void dispose() {
    _events.close();
  }

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    throw UnimplementedError();
  }
}

class _FocusableTerminalRuntime implements TerminalRuntime {
  final StreamController<TerminalRuntimeExitEvent> _events =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> focusedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _events.stream;

  @override
  void closeTab(String tabId) {}

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void dispose() {
    _events.close();
  }

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _FocusableTerminalSessionHandle(
      workspace: workspace,
      tab: tab,
      onFocus: () => focusedTabIds.add(tab.id),
    );
  }
}

class _FocusableTerminalSessionHandle extends TerminalSessionHandle {
  _FocusableTerminalSessionHandle({
    required this.workspace,
    required this.tab,
    required this.onFocus,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final VoidCallback onFocus;

  @override
  String get displayTitle => tab.title;

  @override
  String? get errorMessage => null;

  @override
  bool get isRunning => true;

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
    return SizedBox(key: key);
  }

  @override
  Future<void> ensureStarted() async {}

  @override
  void requestFocus() {
    onFocus();
  }

  @override
  Future<void> restart() async {}
}

class _FakeAwakeDisplayLock implements AgentAwakeDisplayLock {
  final List<bool> states = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    states.add(enabled);
  }
}

class _FakeAwakeAssertion implements AgentAwakeAssertion {
  final List<String> starts = <String>[];
  final List<String> stops = <String>[];

  @override
  Future<void> start(String reason) async {
    starts.add(reason);
  }

  @override
  Future<void> stop(String reason) async {
    stops.add(reason);
  }

  @override
  Future<void> dispose() async {}
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.applicationSupportPath);

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}

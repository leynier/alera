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

/// Collapses the notification coalescing window so a test can assert on the
/// delivery without waiting the real quiet period out.
final _immediateNotificationDelivery = [
  agentStatusNotificationCoalescingProvider.overrideWithValue((
    window: Duration.zero,
    maxDelay: Duration.zero,
  )),
];

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
  Stream<TerminalHostEvent> eventsForSession(String sessionId) =>
      const Stream<TerminalHostEvent>.empty();

  @override
  void releaseSession(String sessionId) {}

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
  Future<TerminalHostResume> setOutputPaused({
    required String sessionId,
    required bool paused,
  }) async {
    return TerminalHostResume(isDelta: true, snapshot: Uint8List(0));
  }

  @override
  Future<void> terminate(String sessionId) async {}

  @override
  Future<bool> reclaimTerminal(String sessionId) async => false;

  @override
  Future<Map<String, TerminalSessionDriver>> listTerminalDrivers() async =>
      const <String, TerminalSessionDriver>{};

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
  Future<Workspace> setWorkspacePinned(
    String workspaceId,
    bool isPinned,
  ) async {
    final current = (await findWorkspaceById(workspaceId))!;
    return upsertWorkspace(current.copyWith(isPinned: isPinned));
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

class _FakeAgentHookServer implements AgentHookServer {
  final _batches = StreamController<AgentHookEventBatch>.broadcast();
  final _enabledAgents = <String>{};

  HttpServer? _server;
  String _token = '';

  @override
  Stream<AgentHookEventBatch> watchEventBatches() => _batches.stream;

  @override
  Future<int> start({
    required String token,
    required List<String> enabledAgents,
  }) async {
    _token = token;
    _enabledAgents
      ..clear()
      ..addAll(enabledAgents);
    final existing = _server;
    if (existing != null) {
      return existing.port;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
    return server.port;
  }

  @override
  Future<void> setEnabledAgents(List<String> enabledAgents) async {
    _enabledAgents
      ..clear()
      ..addAll(enabledAgents);
  }

  @override
  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      await _handle(request);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final agentType = _agentTypeForPath(request.uri.path);
    if (request.method != 'POST' || agentType == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.headers.value(aleraAgentHookTokenHeader) != _token) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (!_enabledAgents.contains(agentType.key)) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    try {
      final bodyBytes = <int>[];
      await for (final chunk in request) {
        bodyBytes.addAll(chunk);
        if (bodyBytes.length > agentHookRequestMaxBytes) {
          throw const FormatException('too large');
        }
      }
      final decoded = decodeAgentHookRequestBody(
        contentType: request.headers.contentType?.toString() ?? '',
        bodyBytes: bodyBytes,
      );
      final event = parseAgentHookRequest(agentType: agentType, body: decoded);
      if (event != null) {
        _batches.add(AgentHookEventBatch(events: <AgentHookEvent>[event]));
      }
    } catch (_) {}
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  AgentType? _agentTypeForPath(String path) {
    if (!path.startsWith('/hook/')) {
      return null;
    }
    final key = path.substring('/hook/'.length);
    for (final agentType in AgentType.values) {
      if (agentType.key == key) {
        return agentType;
      }
    }
    return null;
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

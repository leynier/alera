part of 'alera_shell_page_test.dart';

class _ShellSettingsController(final AleraSettings _seed)
    extends SettingsController {
  @override
  AleraSettings build() => _seed;
}

class const _ShellPumpHarness({
  required final _ShellTestWorkbenchController controller,
  required final _FakeTerminalRuntime runtime,
  required final _ShellTestAgentStatusController agentStatus,
});

class const _FakeManagedWorkspaceRuntime()
    implements ManagedWorkspaceRuntime, WorkspaceStorageRuntime {
  @override
  Future<WorkspaceCreationResult> createLinkedWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    String? name,
  }) => throw UnsupportedError('Workspace creation is not used by shell tests');

  @override
  Future<void> removeWorkspace({
    required Workspace workspace,
    bool? deleteBranch,
    String? activeWorkspaceId,
  }) async {}

  @override
  Future<WorkspaceStorageImpact> storageImpact({
    required String workspaceId,
    String? activeWorkspaceId,
  }) async => WorkspaceStorageImpact(
    workspaceId: workspaceId,
    path: '/host-owned/workspaces/$workspaceId',
    sizeBytes: 4096,
    entryCount: 3,
    measuredAt: .utc(2026, 8, 22, 12),
    lastActivityAt: .utc(2026, 8, 22, 11),
    safeToClean: true,
    blockers: const <String>[],
  );
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
      () => _FakeTerminalSessionHandle(workspace: workspace, tab: tab),
    );
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
    _sessions.remove(tabId)?.dispose();
  }

  /// Total `requestFocus()` calls across every session this runtime created.
  int get totalFocusRequests => _sessions.values.fold<int>(
    0,
    (sum, session) => sum + session.requestFocusCalls,
  );

  /// Tab ids that received at least one `requestFocus()` call.
  Iterable<String> get focusedTabIds => _sessions.entries
      .where((entry) => entry.value.requestFocusCalls > 0)
      .map((entry) => entry.key);

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
  void releaseTab(String tabId) {
    _sessions.remove(tabId)?.dispose();
  }

  @override
  void releaseWorkspace(String workspaceId) {
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

class _FakeTerminalSessionHandle({
  required final Workspace workspace,
  required final WorkspaceTabRecord tab,
}) extends TerminalSessionHandle {
  bool _started = false;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  String get displayTitle => tab.title;

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

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
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return Center(
      key: ValueKey<String>('fake-terminal-${tab.id}'),
      child: Text('Terminal ${tab.title}'),
    );
  }

  int requestFocusCalls = 0;

  @override
  void requestFocus() {
    requestFocusCalls += 1;
  }
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
    bool includeParentEnvironment = true,
  }) {
    throw UnimplementedError();
  }
}

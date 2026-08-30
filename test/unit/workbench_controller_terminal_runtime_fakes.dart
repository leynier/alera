part of 'workbench_controller_test.dart';

class _FakeAgentHookReceiver implements AgentHookReceiver {
  final clearedSessionIds = <String>[];

  @override
  void clearTerminalSession(String terminalSessionId) {
    clearedSessionIds.add(terminalSessionId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> sessions =
      <String, _FakeTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exits =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exits.stream;
  @override
  TerminalSessionHandle? peekSession(String tabId) => sessions[tabId];

  @override
  void setActiveWorkspace(String? workspaceId) {}

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return sessions.putIfAbsent(
      tab.id,
      () => _FakeTerminalSessionHandle(
        tabId: tab.id,
        workspaceId: workspace.id,
        displayTitle: tab.title,
      ),
    );
  }

  final List<String> closedTabIds = <String>[];
  final List<String> closedWorkspaceIds = <String>[];
  final List<String> releasedTabIds = <String>[];
  final List<String> releasedWorkspaceIds = <String>[];

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
    sessions.remove(tabId)?.dispose();
  }

  @override
  void closeWorkspace(String workspaceId) {
    closedWorkspaceIds.add(workspaceId);
    final tabIds = <String>[
      for (final entry in sessions.entries)
        if (entry.value.workspaceId == workspaceId) entry.key,
    ];
    for (final tabId in tabIds) {
      closeTab(tabId);
    }
  }

  @override
  void releaseTab(String tabId) {
    releasedTabIds.add(tabId);
    sessions.remove(tabId)?.dispose();
  }

  @override
  void releaseWorkspace(String workspaceId) {
    releasedWorkspaceIds.add(workspaceId);
    final tabIds = <String>[
      for (final entry in sessions.entries)
        if (entry.value.workspaceId == workspaceId) entry.key,
    ];
    for (final tabId in tabIds) {
      sessions.remove(tabId)?.dispose();
    }
  }

  @override
  Future<void> dispose() => _exits.close();
}

class _FakeTerminalSessionHandle({
  required this.tabId,
  required this.workspaceId,
  required this.displayTitle,
}) extends TerminalSessionHandle {
  @override
  final String tabId;

  @override
  final String workspaceId;

  @override
  final String displayTitle;

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

  int ensureStartedCalls = 0;
  bool failStarts = false;
  bool _running = false;
  String? _errorMessage;

  @override
  bool get isRunning => _running;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> ensureStarted() async {
    ensureStartedCalls += 1;
    if (failStarts) {
      _running = false;
      _errorMessage = 'failed to start';
      notifyListeners();
      return;
    }
    _running = true;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  Future<void> restart() async {
    _running = false;
    await ensureStarted();
  }

  @override
  TerminalVisibilityLease acquireVisibility() {
    return const NoopTerminalVisibilityLease();
  }

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return SizedBox(key: key);
  }

  @override
  void requestFocus() {}
}

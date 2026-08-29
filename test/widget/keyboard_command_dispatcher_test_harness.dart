part of 'keyboard_command_dispatcher_test.dart';

Project _project() {
  return Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/tmp/alera',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
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
  _DispatcherTestWorkbenchController(this._seed, {this.createdTab})
    : _splitCompleter = Completer<WorkspaceTabRecord>();

  final WorkbenchState _seed;
  final WorkspaceTabRecord? createdTab;
  final List<String> sourceBranches = <String>['main'];

  final Completer<WorkspaceTabRecord> _splitCompleter;
  final List<String> createdTerminalWorkspaceIds = <String>[];
  final List<String> createdBrowserWorkspaceIds = <String>[];
  final List<String> closedTabIds = <String>[];
  final List<String> selectedTabIds = <String>[];
  final List<({String workspaceId, String groupId, WorkbenchDropZone zone})>
  splitRequests =
      <({String workspaceId, String groupId, WorkbenchDropZone zone})>[];
  final List<({String workspaceId, String groupId})> mergedSplits =
      <({String workspaceId, String groupId})>[];
  final List<String> navigationCalls = <String>[];

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  void setCollapsed(bool collapsed) {
    state = state.copyWith(collapsed: collapsed);
  }

  @override
  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) {
    splitRequests.add((
      workspaceId: workspace.id,
      groupId: groupId,
      zone: zone,
    ));
    return _splitCompleter.future;
  }

  @override
  Future<WorkspaceTabRecord> createTerminalTab(
    Workspace workspace, {
    String? targetGroupId,
    String? title,
    String? initialCommand,
    bool spawnOnCreate = false,
    bool initialCommandOnce = false,
    bool autoCloseOnSuccess = false,
  }) async {
    createdTerminalWorkspaceIds.add(workspace.id);
    final tab = createdTab ?? _tab(id: 'tab-new');
    final currentTabs = state.tabsFor(workspace.id);
    final layout = state.layoutFor(workspace.id);
    state = state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ...state.tabsByWorkspace,
        workspace.id: <WorkspaceTabRecord>[...currentTabs, tab],
      },
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        if (layout != null)
          workspace.id: layout.addTabToGroup(
            groupId: targetGroupId ?? layout.activeGroupId,
            tabId: tab.id,
          ),
      },
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspace.id: tab.id,
      },
    );
    return tab;
  }

  @override
  Future<WorkspaceTabRecord> createBrowserTab(
    Workspace workspace, {
    String? targetGroupId,
    String? pageId,
    String profileId = 'default',
    String? initialUrl,
  }) async {
    createdBrowserWorkspaceIds.add(workspace.id);
    return WorkspaceTabRecord(
      id: 'browser-tab-new',
      workspaceId: workspace.id,
      kind: WorkspaceTabKind.browser,
      title: 'New Tab',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      payload: <String, Object?>{
        workspaceTabBrowserProfileIdPayloadKey: profileId,
      },
    );
  }

  @override
  Future<void> closeWorkspaceTab({
    required Workspace workspace,
    required String tabId,
  }) async {
    closedTabIds.add(tabId);
  }

  @override
  void setActiveWorkspaceTab({
    required String workspaceId,
    required String groupId,
    required String tabId,
  }) {
    selectedTabIds.add(tabId);
    final layout = state.layoutFor(workspaceId);
    if (layout == null) {
      return;
    }
    state = state.copyWith(
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        workspaceId: layout.setActiveTab(groupId: groupId, tabId: tabId),
      },
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspaceId: tabId,
      },
    );
  }

  @override
  Future<void> mergeWorkbenchGroupIntoSibling({
    required String workspaceId,
    required String groupId,
  }) async {
    mergedSplits.add((workspaceId: workspaceId, groupId: groupId));
  }

  @override
  Future<void> goBack() async {
    navigationCalls.add('back');
  }

  @override
  Future<void> goForward() async {
    navigationCalls.add('forward');
  }

  @override
  Future<List<String>> listSourceBranches(Project project) async {
    return sourceBranches;
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
  final List<String> closedTabIds = <String>[];
  final Set<String> everFocusedTabIds = <String>{};

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  Iterable<String> get focusedTabIds => _sessions.entries
      .where((entry) => entry.value.requestFocusCalls > 0)
      .map((entry) => entry.key);

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
      () => _FakeTerminalSessionHandle(
        workspace: workspace,
        tab: tab,
        onFocus: () => everFocusedTabIds.add(tab.id),
      ),
    );
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
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
  void releaseTab(String tabId) {
    _sessions.remove(tabId)?.dispose();
  }

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

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({
    required this.workspace,
    required this.tab,
    required this.onFocus,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final VoidCallback onFocus;
  int requestFocusCalls = 0;

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
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

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
    onFocus();
  }
}

class _DispatcherPumpHarness {
  const _DispatcherPumpHarness({required this.ref, required this.context});

  final WidgetRef ref;
  final BuildContext context;
}

Future<_DispatcherPumpHarness> _pumpDispatcherHarness(
  WidgetTester tester, {
  required _DispatcherTestWorkbenchController controller,
  required _FakeTerminalRuntime runtime,
}) async {
  final container = ProviderContainer(
    overrides: [
      workbenchControllerProvider.overrideWith(() => controller),
      agentProfilesProvider.overrideWith(() => _DispatcherAgentProfiles()),
      terminalRuntimeProvider.overrideWith((ref) => runtime),
      browserAvailabilityProvider.overrideWith(
        (ref) => _stableBrowserCapabilities,
      ),
      settingsControllerProvider.overrideWith(
        () => _DispatcherSettingsController(AleraSettings.defaults),
      ),
    ],
  );
  addTearDown(container.dispose);

  late WidgetRef dispatcherRef;
  late BuildContext dispatcherContext;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            dispatcherRef = ref;
            dispatcherContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return _DispatcherPumpHarness(ref: dispatcherRef, context: dispatcherContext);
}

const BrowserEngineCapabilities _stableBrowserCapabilities =
    BrowserEngineCapabilities(
      engine: 'test',
      engineAvailable: true,
      pageSurface: true,
      isolatedProfiles: true,
      ephemeralProfiles: true,
      deterministicPageClose: true,
      navigation: true,
      navigationEvents: true,
      javascript: true,
      basicCookies: true,
      fullCookies: true,
      permissionCallbacks: true,
      tlsCallbacks: true,
      tlsTrustScope: 'profileSession',
      popupCallbacks: true,
      downloadCallbacks: true,
      domSnapshot: true,
      domActions: true,
      viewportScreenshot: true,
      fullPageScreenshot: true,
      pdf: true,
      flutterOverlayOcclusion: true,
      atomicCookieImport: true,
      manualJsonCookieImport: true,
      nativeCookieImportSources: <String>{'test', 'manualJson'},
      requiredNativeCookieImportSources: <String>{'test', 'manualJson'},
    );

class _DispatcherSettingsController extends SettingsController {
  _DispatcherSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}

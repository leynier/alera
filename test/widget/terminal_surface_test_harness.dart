part of 'terminal_surface_test.dart';

WorkspaceTabRecord _tab({
  String id = 'tab-1',
  String workspaceId = 'ws-1',
  String title = 'Terminal 1',
}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    title: title,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

Workspace _workspace({String id = 'ws-1', String path = '/tmp/alera'}) {
  return Workspace(
    id: id,
    projectId: 'p-1',
    name: 'Main',
    branch: 'main',
    path: path,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

/// The runtime paces terminal flushes, so freshly emitted PTY output is not on
/// screen after a single frame. Waits out that cadence, then renders it.
Future<void> _pumpTerminalOutput(WidgetTester tester) async {
  await tester.pump(terminalOutputMinFlushIntervalForTesting);
  await tester.pump();
}

Future<void> _pumpTerminalSurface(
  WidgetTester tester,
  TerminalSessionHandle session,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(child: TerminalSurface(session: session)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

List<GhosttyTerminalShellLaunch> _testShellLaunches() {
  return const <GhosttyTerminalShellLaunch>[
    GhosttyTerminalShellLaunch(
      label: 'sh',
      shell: '/bin/sh',
      arguments: <String>['-i'],
      environment: <String, String>{'TERM': 'xterm-256color'},
    ),
  ];
}

Offset _cellCenter(WidgetTester tester, xterm.CellOffset offset) {
  final terminalViewState = tester.state<xterm.TerminalViewState>(
    find.byType(xterm.TerminalView),
  );
  final renderTerminal = terminalViewState.renderTerminal;
  final localOffset =
      renderTerminal.getOffset(offset) +
      Offset(
        renderTerminal.cellSize.width / 2,
        renderTerminal.cellSize.height / 2,
      );
  return renderTerminal.localToGlobal(localOffset);
}

class _FakeTerminalPtySessionFactory implements TerminalPtySessionFactory {
  final List<_FakeTerminalPtySession> sessions = <_FakeTerminalPtySession>[];

  @override
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    final session = _FakeTerminalPtySession();
    sessions.add(session);
    return session;
  }
}

class _FakeTerminalPtySession implements TerminalPtySession {
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  final List<List<int>> writes = <List<int>>[];
  final List<bool> outputPausedCalls = <bool>[];
  GhosttyTerminalShellLaunch? startedLaunch;
  int? startedCols;
  int? startedRows;
  String? startedWorkingDirectory;
  bool disposed = false;
  bool terminated = false;
  int? exitCodeOnDispose;
  Completer<void>? nextResumeCompleter;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  bool get startedNewProcess => true;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
    Future<void> Function()? onProcessCreated,
  }) async {
    startedLaunch = launch;
    startedWorkingDirectory = workingDirectory;
    startedCols = cols;
    startedRows = rows;
    await onProcessCreated?.call();
  }

  @override
  bool writeBytes(List<int> bytes) {
    writes.add(List<int>.from(bytes));
    return bytes.isNotEmpty;
  }

  @override
  Future<bool> writeBytesAndWait(List<int> bytes) async => writeBytes(bytes);

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {}

  @override
  Future<void> refreshViewport(
    int cols,
    int rows,
    int cellWidthPx,
    int cellHeightPx,
  ) async {}

  @override
  Future<void> setOutputPaused(bool paused) async {
    outputPausedCalls.add(paused);
    if (paused) {
      return;
    }
    final completer = nextResumeCompleter;
    nextResumeCompleter = null;
    await completer?.future;
  }

  void emitExit(int exitCode) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyExitEvent(exitCode));
  }

  void emitOutput(List<int> data) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyOutputEvent(Uint8List.fromList(data)));
  }

  void emitError(Object error) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyErrorEvent(error));
  }

  @override
  void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    if (exitCodeOnDispose case final exitCode?) {
      _events.add(TerminalPtyExitEvent(exitCode));
    }
    unawaited(_events.close());
  }

  @override
  void terminate() {
    terminated = true;
    dispose();
  }
}

class _ImmediateNotifySessionHandle extends TerminalSessionHandle {
  _ImmediateNotifySessionHandle({required this.tabId, this.refreshCompleter});

  @override
  final String tabId;
  final Completer<void>? refreshCompleter;

  int ensureStartedCallCount = 0;
  int refreshRenderingCallCount = 0;
  bool _started = false;

  @override
  String get workspaceId => 'workspace-1';

  @override
  String get displayTitle => 'Terminal';

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

  @override
  bool get isRunning => _started;

  @override
  bool get isStarting => !_started;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {
    ensureStartedCallCount += 1;
    _started = true;
    notifyListeners();
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
    return SizedBox.expand(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  Future<void> refreshRendering() async {
    refreshRenderingCallCount += 1;
    await refreshCompleter?.future;
  }

  @override
  void requestFocus() {}
}

class _ShortcutCaptureSessionHandle extends TerminalSessionHandle {
  _ShortcutCaptureSessionHandle({required this.tabId});

  @override
  final String tabId;

  FocusOnKeyEventCallback? onKeyEvent;

  @override
  String get workspaceId => 'workspace-1';

  @override
  String get displayTitle => 'Terminal';

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
    this.onKeyEvent = onKeyEvent;
    return Container(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  void requestFocus() {}
}

class _FakeWorkbenchController extends WorkbenchController {
  final List<bool> collapsedValues = <bool>[];

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  void setCollapsed(bool value) {
    collapsedValues.add(value);
    state = state.copyWith(collapsed: value);
  }
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this.settings);

  AleraSettings settings;

  @override
  AleraSettings build() => settings;
}

class _ErrorSessionHandle extends TerminalSessionHandle {
  _ErrorSessionHandle({required this.tabId, required this.message});

  @override
  final String tabId;

  final String message;
  int restartCallCount = 0;

  @override
  String get workspaceId => 'workspace-1';

  @override
  String get displayTitle => 'Terminal';

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

  @override
  bool get isRunning => false;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => message;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> restart() async {
    restartCallCount += 1;
  }

  @override
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return SizedBox.expand(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  void requestFocus() {}
}

class _StartingSessionHandle extends TerminalSessionHandle {
  _StartingSessionHandle({required this.tabId});

  @override
  final String tabId;

  @override
  String get workspaceId => 'workspace-1';

  @override
  String get displayTitle => 'Terminal';

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

  @override
  bool get isRunning => false;

  @override
  bool get isStarting => true;

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
    return SizedBox.expand(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  void requestFocus() {}
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  _FakeExternalUriLauncher({this.error});

  final Object? error;
  final List<Uri> openedUris = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    if (error case final Object error) {
      throw error;
    }
    openedUris.add(uri);
  }
}

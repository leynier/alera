part of 'terminal_runtime.dart';

class _XtermTerminalSessionHandle extends TerminalSessionHandle
    with _TerminalSearchSessionSupport {
  _XtermTerminalSessionHandle(
    this._workspace,
    this._tab,
    this._ptySessionFactory,
    this._settings,
    this._externalUriLauncher,
    this._shellLaunchesBuilder,
    this._agentHookEnvironmentBuilder,
    this._shellStartupPreparer,
    this._terminalProcessCreated,
    this._clipboard,
    this._interactionNotice,
    this._osc52Blocked,
    this._onExit,
    this._onVisibilityChanged,
  ) {
    _terminal = _createTerminal();
    _osc8LinkTracker = Osc8TerminalLinkTracker(terminal: _terminal);
    _attachTerminal(_terminal);
    _terminalController.addListener(_handleSelectionChanged);
    _decodedOutputSub = _ptyOutputController.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_handleTerminalOutput);
  }

  Workspace _workspace;
  WorkspaceTabRecord _tab;
  final TerminalPtySessionFactory _ptySessionFactory;
  final ExternalUriLauncher _externalUriLauncher;
  final List<GhosttyTerminalShellLaunch> Function() _shellLaunchesBuilder;
  final TerminalLaunchEnvironmentBuilder? _agentHookEnvironmentBuilder;
  final TerminalShellStartupPreparer? _shellStartupPreparer;
  final TerminalProcessCreated? _terminalProcessCreated;
  final TerminalClipboard _clipboard;
  final void Function(String message, {bool error})? _interactionNotice;
  final VoidCallback _osc52Blocked;
  final void Function(TerminalRuntimeExitEvent event) _onExit;

  /// Lets the runtime re-run the memory budget when a terminal stops being
  /// visible, which is the only moment a new eviction candidate appears.
  final void Function(_XtermTerminalSessionHandle handle) _onVisibilityChanged;
  TerminalSettings _settings;
  @override
  late xterm.Terminal _terminal;
  @override
  late Osc8TerminalLinkTracker _osc8LinkTracker;
  @override
  final GlobalKey<xterm.TerminalViewState> _terminalViewKey =
      GlobalKey<xterm.TerminalViewState>();
  @override
  final xterm.TerminalController _terminalController = xterm.TerminalController(
    pointerInputs: const xterm.PointerInputs.all(),
  );

  /// Survives TerminalSurface dispose/rebuild so scroll position is preserved
  /// when switching tabs and coming back.
  @override
  final ScrollController _scrollController = ScrollController();
  @override
  final FocusNode _focusNode = FocusNode(debugLabel: 'TerminalSession');
  @override
  final StreamController<List<int>> _ptyOutputController =
      StreamController<List<int>>();
  @override
  late final StreamSubscription<String> _decodedOutputSub;

  final _TerminalOutputPipeline _output = _TerminalOutputPipeline();
  TerminalPtySession? _ptySession;
  StreamSubscription<TerminalPtySessionEvent>? _ptySessionSub;
  Timer? _pendingPtyResizeTimer;
  Timer? _selectionCopyTimer;
  _TerminalPtySize? _pendingPtySize;
  int _ptyGeneration = 0;
  @override
  int _startAttempt = 0;
  int? _activePtyGeneration;
  final Set<int> _exitedPtyGenerations = <int>{};
  final Set<int> _suppressedExitPtyGenerations = <int>{};
  @override
  final Set<Object> _visibilityLeases = <Object>{};

  bool _starting = false;
  TerminalSessionOperation? _operation;
  bool _started = false;
  bool _running = false;
  String _title = '';
  @override
  late final ValueNotifier<String> _titleNotifier = ValueNotifier<String>(
    displayTitle,
  );
  String? _errorMessage;
  @override
  bool _visible = false;
  DateTime? _lastVisibleAt;
  @override
  final ValueNotifier<TerminalRestoreProgress?> _restoreProgress =
      ValueNotifier<TerminalRestoreProgress?>(null);
  int _restoreGeneration = 0, _restoreTotalChars = 0, _restoreWrittenChars = 0;
  bool _pendingInteractionModeReset = false;
  @override
  int _pointerInputCatchUpChars = 0;
  @override
  bool _pointerInputResumePending = false;
  @override
  int _outputVisibilityGeneration = 0;
  @override
  bool _disposed = false;

  @override
  String get tabId => _tab.id;

  @override
  String get workspaceId => _workspace.id;

  String get terminalSessionId => _tab.terminalSessionId;

  @override
  ValueListenable<String> get titleListenable => _titleNotifier;

  @override
  bool get isVisible => _visible;

  @override
  ValueListenable<TerminalRestoreProgress?> get restoreProgress =>
      _restoreProgress;

  @override
  TerminalBufferUsage get bufferUsage => _estimateBufferUsage();

  @override
  String get displayTitle {
    if (_tab.hasManualTitle) {
      return _tab.title;
    }
    final runtimeTitle = _title.trim();
    if (runtimeTitle.isEmpty || runtimeTitle == 'Terminal') {
      return _tab.title;
    }
    return runtimeTitle;
  }

  @override
  bool get isRunning => _running;

  @override
  bool get isStarting => _starting;

  @override
  TerminalSessionOperation? get operation => _operation;

  @override
  bool get canRestart {
    final session = _ptySession;
    return session is RecoverableTerminalPtySession && session.supportsRestart;
  }

  @override
  String? get errorMessage => _errorMessage;

  _XtermTerminalSessionHandle sync({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    final metadataChanged =
        _workspace.id != workspace.id ||
        _workspace.path != workspace.path ||
        _tab.id != tab.id ||
        _tab.title != tab.title ||
        _tab.hasManualTitle != tab.hasManualTitle;
    _workspace = workspace;
    _tab = tab;
    _titleNotifier.value = displayTitle;
    if (metadataChanged) {
      // sync() is invoked from build(); defer the notification so listening
      // AnimatedBuilders are not marked dirty during the build phase.
      scheduleMicrotask(() {
        if (!_disposed) {
          notifyListeners();
        }
      });
    }
    return this;
  }

  void applySettings(TerminalSettings settings) {
    _settings = settings;
    if (!settings.clipboardOnSelect) {
      _selectionCopyTimer?.cancel();
      _selectionCopyTimer = null;
    } else {
      _handleSelectionChanged();
    }
    notifyListeners();
  }

  @override
  Future<void> ensureStarted() => _ensureTerminalSessionStarted(this);

  @override
  Future<void> reconnect() => _reconnectTerminalSession(this);

  @override
  Future<void> restart() => _restartTerminalSession(this);

  void _notifySessionListeners() => notifyListeners();

  @override
  TerminalVisibilityLease acquireVisibility() {
    if (_disposed) {
      return const NoopTerminalVisibilityLease();
    }
    final token = Object();
    _visibilityLeases.add(token);
    _syncVisibilityFromLeases();
    return _TerminalVisibilityLease(() {
      if (_disposed || !_visibilityLeases.remove(token)) {
        return;
      }
      _syncVisibilityFromLeases();
    });
  }

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return _InteractiveTerminalView(
      key: key,
      session: this,
      autofocus: autofocus,
      onKeyEvent: onKeyEvent,
    );
  }

  xterm.TerminalView _buildTerminalView({
    required bool autofocus,
    FocusOnKeyEventCallback? onKeyEvent,
    required MouseCursor mouseCursor,
    void Function(TapUpDetails details, xterm.CellOffset offset)? onTapUp,
  }) {
    return xterm.TerminalView(
      _terminal,
      key: _terminalViewKey,
      controller: _terminalController,
      scrollController: _scrollController,
      focusNode: _focusNode,
      autofocus: autofocus,
      onTapUp: onTapUp,
      onKeyEvent: onKeyEvent,
      mouseCursor: mouseCursor,
      theme: _resolveXtermTheme(_settings),
      textStyle: xterm.TerminalStyle(
        fontSize: _settings.fontSize,
        fontWeight: _settings.fontWeight,
        height: _settings.lineHeight,
        fontFamily: _resolveTerminalFontFamily(_settings.fontFamily),
        fontFamilyFallback: _terminalFontFallback,
      ),
      padding: EdgeInsets.fromLTRB(
        _settings.paddingX,
        _settings.paddingY,
        _settings.paddingX,
        _settings.paddingY,
      ),
      cursorType: _settings.cursorShape.toXtermCursorType(),
      cursorBlink: _settings.cursorBlink,
      backgroundOpacity: _settings.backgroundOpacity,
      hardwareKeyboardOnly: _terminalHardwareKeyboardOnly,
      mouseWheelSensitivity: _settings.tuiScrollSensitivity.clamp(1, 10),
      onPaste: _pasteFromClipboard,
      onCopy: _clipboard.writeText,
    );
  }

  TerminalLinkRange? _linkAt(xterm.CellOffset offset) {
    return resolveTerminalLinkAt(
      terminal: _terminal,
      offset: offset,
      osc8Tracker: _osc8LinkTracker,
    );
  }

  Future<void> _openLink(Uri uri) {
    return _externalUriLauncher.open(uri);
  }

  void _handleTitleChanged(String title) {
    _title = title;
    _titleNotifier.value = displayTitle;
  }

  void _handleTerminalInput(String data) {
    _ptySession?.writeBytes(utf8.encode(data));
  }

  void _handleTerminalResize(
    int width,
    int height,
    int pixelWidth,
    int pixelHeight,
  ) {
    _pendingPtySize = _TerminalPtySize(
      cols: width,
      rows: height,
      cellWidthPx: pixelWidth,
      cellHeightPx: pixelHeight,
    );
    _pendingPtyResizeTimer ??= Timer(
      _ptyResizeDebounceDuration,
      _flushPendingPtyResize,
    );
  }

  void _flushPendingPtyResize() {
    _pendingPtyResizeTimer?.cancel();
    _pendingPtyResizeTimer = null;
    final size = _pendingPtySize;
    final session = _ptySession;
    if (_disposed || size == null) {
      _pendingPtySize = null;
      return;
    }
    if (session == null) {
      return;
    }
    _pendingPtySize = null;
    session.resize(size.cols, size.rows, size.cellWidthPx, size.cellHeightPx);
  }

  @override
  Future<void> refreshRendering() async {
    if (_disposed) {
      return;
    }
    final session = _ptySession;
    if (session == null) {
      return;
    }
    final viewState = _terminalViewKey.currentState;
    if (viewState == null) {
      return;
    }
    final renderTerminal = viewState.renderTerminal;
    if (!renderTerminal.attached ||
        !renderTerminal.hasSize ||
        renderTerminal.size.isEmpty) {
      return;
    }
    final cellSize = renderTerminal.cellSize;
    await session.refreshViewport(
      _terminal.viewWidth,
      _terminal.viewHeight,
      cellSize.width.round(),
      cellSize.height.round(),
    );
    if (_disposed ||
        !identical(_terminalViewKey.currentState, viewState) ||
        !renderTerminal.attached) {
      return;
    }
    renderTerminal.markNeedsLayout();
    renderTerminal.markNeedsPaint();
  }

  Future<bool> _startPtySession() async {
    final launches = _shellLaunchesBuilder();
    if (launches.isEmpty) {
      throw StateError(_noTerminalShellCandidatesMessage());
    }
    final agentHookEnvironment = await _agentHookEnvironmentBuilder?.call(
      terminalSessionId: _tab.terminalSessionId,
      workspaceId: _workspace.id,
      tabId: _tab.id,
    );
    Object? lastError;
    for (final launch in launches) {
      final session = _ptySessionFactory.create(
        sessionId: _tab.terminalSessionId,
        workspaceId: _workspace.id,
        tabId: _tab.id,
      );
      final generation = ++_ptyGeneration;
      final sub = session.events.listen(
        (event) => _handlePtySessionEvent(event, generation),
      );
      _activePtyGeneration = generation;
      try {
        final sanitizedLaunch = _launchWithSanitizedAgentHookEnvironment(
          _settings.resolvedLoginShell ? _launchAsLoginShell(launch) : launch,
          agentHookEnvironment,
        );
        final workspaceAwarePowerShellLaunch =
            _isWindowsPowerShellLaunch(sanitizedLaunch)
            ? _launchInWorkingDirectory(sanitizedLaunch, _workspace.path)
            : null;
        final preparedLaunch = await _shellStartupPreparer?.prepare(
          workspaceAwarePowerShellLaunch ?? sanitizedLaunch,
        );
        final interactiveLaunch =
            preparedLaunch ?? workspaceAwarePowerShellLaunch ?? sanitizedLaunch;
        final workspaceLaunch = workspaceAwarePowerShellLaunch == null
            ? _launchInWorkingDirectory(interactiveLaunch, _workspace.path)
            : interactiveLaunch;
        await session.start(
          launch: workspaceLaunch,
          workingDirectory: _workspace.path,
          cols: _terminal.viewWidth,
          rows: _terminal.viewHeight,
          onProcessCreated: () async {
            bool isCurrent() =>
                !_disposed && _activePtyGeneration == generation;
            if (!isCurrent()) {
              return;
            }
            await _terminalProcessCreated?.call(_tab.terminalSessionId);
            if (!isCurrent()) {
              return;
            }
            await _deliverTerminalProcessStartup(
              session: session,
              launch: workspaceLaunch,
              interactiveShell: interactiveLaunch.shell,
              initialCommand: _tab.initialCommand,
              isCurrent: isCurrent,
            );
          },
        );
        if (_disposed || _activePtyGeneration != generation) {
          unawaited(sub.cancel());
          session.dispose();
          _prunePtyGenerationState();
          return false;
        }
        _ptySession = session;
        _ptySessionSub = sub;
        if (!_visible) {
          _syncPtyOutputVisibility();
        }
        _flushPendingPtyResize();
        _running = !_exitedPtyGenerations.contains(generation);
        _prunePtyGenerationState();
        notifyListeners();
        return !_disposed &&
            _activePtyGeneration == generation &&
            identical(_ptySession, session);
      } catch (error) {
        if (_disposed || _activePtyGeneration != generation) {
          unawaited(sub.cancel());
          session.dispose();
          _prunePtyGenerationState();
          return false;
        }
        lastError = error;
        _suppressedExitPtyGenerations.add(generation);
        if (_activePtyGeneration == generation) {
          _activePtyGeneration = null;
        }
        if (identical(_ptySession, session)) {
          _ptySession = null;
        }
        if (identical(_ptySessionSub, sub)) {
          _ptySessionSub = null;
        }
        unawaited(sub.cancel());
        session.dispose();
        _prunePtyGenerationState();
      }
    }
    throw StateError('No desktop PTY shell could be started: $lastError');
  }

  void _handlePtySessionEvent(TerminalPtySessionEvent event, int generation) {
    if (_disposed || generation != _activePtyGeneration) {
      return;
    }
    switch (event) {
      // Output that arrives while hidden is queued, not dropped. The host
      // counts a frame as delivered the moment the client's queue takes it, so
      // discarding between losing visibility and the pause taking effect would
      // leave a gap that no later resume knows to resend.
      case TerminalPtyOutputEvent(:final data):
        _ptyOutputController.add(data);
      case TerminalPtyOutputTextEvent(:final text):
        // Already decoded by the reader isolate, so it skips the local
        // decoder entirely.
        _handleTerminalOutput(text);
      case TerminalPtySnapshotEvent(:final data, :final resetInteractionModes):
        _pendingInteractionModeReset |= resetInteractionModes;
        if (_visible) {
          final shouldResetInteractionModes = _pendingInteractionModeReset;
          _preparePointerInputForSnapshot();
          _replaceTerminalWithSnapshot(
            data,
            resetInteractionModes: shouldResetInteractionModes,
          );
          _completePointerInputSnapshotCatchUp();
          _pendingInteractionModeReset = false;
        }
      case TerminalPtyExitEvent(:final exitCode):
        _handlePtyExit(
          exitCode: exitCode,
          generation: generation,
          notifyRuntime: event.notifyRuntime,
        );
      case TerminalPtyErrorEvent(:final error):
        _setTerminalHostError(error);
    }
  }

  void _handlePtyExit({
    required int exitCode,
    required int generation,
    required bool notifyRuntime,
  }) {
    if (!_exitedPtyGenerations.add(generation)) {
      return;
    }
    _running = false;
    _flushPendingTerminalOutputNow();
    _writeToTerminal(terminalInteractionModeReset);
    _writeToTerminal('\n[process exited: $exitCode]\n');
    notifyListeners();
    if (notifyRuntime && !_suppressedExitPtyGenerations.contains(generation)) {
      _onExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspaceId,
          tabId: tabId,
          exitCode: exitCode,
          autoCloseOnSuccess: _tab.autoCloseOnSuccess,
        ),
      );
    }
    unawaited(_stopPtySessionWithMode(suppressExit: true, terminate: false));
  }

  void _handlePrivateOsc(String code, List<String> args) {
    _handleTerminalPrivateOsc(this, code, args);
  }

  Future<void> _pasteFromClipboard() => _pasteTerminalClipboard(this);

  @override
  void _handleSelectionChanged() {
    _handleTerminalSelectionChanged(this);
  }

  void _notifyInteraction(String message, {bool error = false}) {
    _publishTerminalInteraction(this, message, error: error);
  }

  xterm.Terminal _createTerminal() => _createSessionTerminal(this);

  void _attachTerminal(xterm.Terminal terminal) {
    _attachSessionTerminal(this, terminal);
  }

  @override
  void _detachTerminal(xterm.Terminal terminal) {
    _detachSessionTerminal(terminal);
  }

  void _handleTerminalOutput(String data) => _queueTerminalOutput(data);

  void _writeToTerminal(String data) => _writeSessionTerminal(this, data);

  void _queueTerminalOutput(
    String data, {
    _TerminalOutputSource source = _TerminalOutputSource.live,
  }) => _queueSessionTerminalOutput(this, data, source: source);

  void _scheduleTerminalOutputFlush() =>
      _scheduleSessionTerminalOutputFlush(this);

  void _flushPendingTerminalOutputFrame() =>
      _flushSessionTerminalOutputFrame(this);

  void _flushPendingTerminalOutputNow() => _flushSessionTerminalOutputNow(this);

  void _replaceTerminalWithSnapshot(
    List<int> data, {
    required bool resetInteractionModes,
  }) {
    _rebuildTerminalFromSnapshot(
      data,
      resetInteractionModes: resetInteractionModes,
    );
    notifyListeners();
  }

  @override
  void _clearPendingTerminalOutput() {
    _output.cancelDeferredFlush();
    _output.clear();
  }

  void _setTerminalHostError(Object error) {
    if (_disposed) {
      return;
    }
    final message = 'Terminal host unavailable: $error';
    if (_errorMessage == message) {
      return;
    }
    _errorMessage = message;
    notifyListeners();
  }

  Future<void> _stopPtySession({required bool suppressExit}) async {
    await _stopPtySessionWithMode(suppressExit: suppressExit, terminate: true);
  }

  @override
  Future<void> _stopPtySessionWithMode({
    required bool suppressExit,
    required bool terminate,
  }) async {
    _pendingPtyResizeTimer?.cancel();
    _pendingPtyResizeTimer = null;
    _pendingPtySize = null;
    _selectionCopyTimer?.cancel();
    _selectionCopyTimer = null;
    final generation = _activePtyGeneration;
    if (suppressExit && generation != null) {
      _suppressedExitPtyGenerations.add(generation);
    }
    if (_activePtyGeneration == generation) {
      _activePtyGeneration = null;
    }
    final sub = _ptySessionSub;
    _ptySessionSub = null;
    await sub?.cancel();
    final session = _ptySession;
    _ptySession = null;
    if (terminate) {
      session?.terminate();
    } else {
      session?.dispose();
    }
    _prunePtyGenerationState();
  }

  void _prunePtyGenerationState() {
    final active = _activePtyGeneration;
    _exitedPtyGenerations.removeWhere((generation) => generation != active);
    _suppressedExitPtyGenerations.removeWhere(
      (generation) => generation != active,
    );
  }

  @override
  void requestFocus() {
    // Defer to the next frame so the terminal view is mounted (e.g. after
    // switching workspaces) before we ask the FocusNode to claim focus.
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocusNow());
  }

  @override
  void pasteText(String text) => _pasteTerminalText(this, text);

  void _requestFocusNow() {
    if (_disposed || !_focusNode.canRequestFocus) {
      return;
    }
    _focusNode.requestFocus();
  }
}

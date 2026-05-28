part of 'terminal_runtime.dart';

class _XtermTerminalSessionHandle extends TerminalSessionHandle {
  _XtermTerminalSessionHandle(
    this._workspace,
    this._tab,
    this._ptySessionFactory,
    this._settings,
    this._externalUriLauncher,
    this._shellLaunchesBuilder,
    this._agentHookEnvironmentBuilder,
    this._shellStartupPreparer,
    this._onExit,
  ) {
    _terminal = _createTerminal();
    _osc8LinkTracker = Osc8TerminalLinkTracker(terminal: _terminal);
    _attachTerminal(_terminal);
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
  final void Function(TerminalRuntimeExitEvent event) _onExit;
  TerminalSettings _settings;
  late xterm.Terminal _terminal;
  late final Osc8TerminalLinkTracker _osc8LinkTracker;
  final GlobalKey<xterm.TerminalViewState> _terminalViewKey =
      GlobalKey<xterm.TerminalViewState>();
  final xterm.TerminalController _terminalController =
      xterm.TerminalController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'TerminalSession');
  final StreamController<List<int>> _ptyOutputController =
      StreamController<List<int>>();
  late final StreamSubscription<String> _decodedOutputSub;
  TerminalPtySession? _ptySession;
  StreamSubscription<TerminalPtySessionEvent>? _ptySessionSub;
  Timer? _pendingPtyResizeTimer;
  _TerminalPtySize? _pendingPtySize;
  int _ptyGeneration = 0;
  int? _activePtyGeneration;
  final Set<int> _exitedPtyGenerations = <int>{};
  final Set<int> _suppressedExitPtyGenerations = <int>{};

  bool _starting = false;
  bool _started = false;
  bool _running = false;
  String _title = '';
  String? _errorMessage;
  bool _disposed = false;

  @override
  String get tabId => _tab.id;

  @override
  String get workspaceId => _workspace.id;

  String get terminalSessionId => _tab.terminalSessionId;

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
    notifyListeners();
  }

  @override
  Future<void> ensureStarted() async {
    if (_started || _starting) {
      return;
    }
    _starting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (!_isSupportedNativeDesktopTerminalPlatform) {
        throw UnsupportedError(
          'Terminal sessions require a native desktop PTY path.',
        );
      }
      await _startPtySession();
      _started = true;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  @override
  Future<void> restart() async {
    _errorMessage = null;
    _started = false;
    _starting = false;
    _running = false;
    notifyListeners();
    await _stopPtySession(suppressExit: true);
    await ensureStarted();
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
    notifyListeners();
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
    _pendingPtyResizeTimer = null;
    final size = _pendingPtySize;
    _pendingPtySize = null;
    final session = _ptySession;
    if (_disposed || size == null || session == null) {
      return;
    }
    session.resize(size.cols, size.rows, size.cellWidthPx, size.cellHeightPx);
  }

  Future<void> _startPtySession() async {
    final launches = _shellLaunchesBuilder();
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
      _ptySession = session;
      _ptySessionSub = sub;
      _activePtyGeneration = generation;
      try {
        final sanitizedLaunch = _launchWithSanitizedAgentHookEnvironment(
          launch,
          agentHookEnvironment,
        );
        final preparedLaunch = await _shellStartupPreparer?.prepare(
          sanitizedLaunch,
        );
        final workspaceLaunch = _launchInWorkingDirectory(
          preparedLaunch ?? sanitizedLaunch,
          _workspace.path,
        );
        await session.start(
          launch: workspaceLaunch,
          workingDirectory: _workspace.path,
          cols: _terminal.viewWidth,
          rows: _terminal.viewHeight,
        );
        _running = true;
        _prunePtyGenerationState();
        notifyListeners();
        final setupCommand = workspaceLaunch.setupCommand;
        if (session.startedNewProcess &&
            setupCommand != null &&
            setupCommand.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          session.writeBytes(utf8.encode(setupCommand));
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        return;
      } catch (error) {
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
      case TerminalPtyOutputEvent(:final data):
        _ptyOutputController.add(data);
      case TerminalPtyExitEvent(:final exitCode):
        _handlePtyExit(
          exitCode: exitCode,
          generation: generation,
          notifyRuntime: event.notifyRuntime,
        );
      case TerminalPtyErrorEvent(:final error):
        _writeToTerminal('\n[terminal error: $error]\n');
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
    _writeToTerminal('\n[process exited: $exitCode]\n');
    notifyListeners();
    if (notifyRuntime && !_suppressedExitPtyGenerations.contains(generation)) {
      _onExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspaceId,
          tabId: tabId,
          exitCode: exitCode,
        ),
      );
    }
    unawaited(
      _stopPtySessionWithMode(suppressExit: true, terminate: notifyRuntime),
    );
  }

  void _handlePrivateOsc(String code, List<String> args) {
    _osc8LinkTracker.handlePrivateOsc(code, args);
  }

  xterm.Terminal _createTerminal() {
    return xterm.Terminal(
      maxLines: _settings.scrollbackLines,
      platform: _xtermTargetPlatform,
      wordSeparators: _wordSeparatorsFromSettings(_settings.wordSeparators),
    );
  }

  void _attachTerminal(xterm.Terminal terminal) {
    terminal.onTitleChange = _handleTitleChanged;
    terminal.onOutput = _handleTerminalInput;
    terminal.onResize = _handleTerminalResize;
    terminal.onPrivateOSC = _handlePrivateOsc;
  }

  void _detachTerminal(xterm.Terminal terminal) {
    terminal.onTitleChange = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    terminal.onPrivateOSC = null;
  }

  void _handleTerminalOutput(String data) {
    _writeToTerminal(data);
  }

  void _writeToTerminal(String data) {
    if (data.isEmpty || _disposed) {
      return;
    }
    _terminal.write(data);
  }

  Future<void> _stopPtySession({required bool suppressExit}) async {
    await _stopPtySessionWithMode(suppressExit: suppressExit, terminate: true);
  }

  Future<void> _stopPtySessionWithMode({
    required bool suppressExit,
    required bool terminate,
  }) async {
    _pendingPtyResizeTimer?.cancel();
    _pendingPtyResizeTimer = null;
    _pendingPtySize = null;
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
  void dispose({bool terminatePty = true}) {
    _disposed = true;
    _osc8LinkTracker.dispose();
    _detachTerminal(_terminal);
    unawaited(
      _stopPtySessionWithMode(suppressExit: true, terminate: terminatePty),
    );
    unawaited(_decodedOutputSub.cancel());
    unawaited(_ptyOutputController.close());
    _focusNode.dispose();
    super.dispose();
  }

  void _requestFocusNow() {
    if (_disposed || !_focusNode.canRequestFocus) {
      return;
    }
    _focusNode.requestFocus();
  }
}

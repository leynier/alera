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
    this._terminalProcessCreated,
    this._clipboard,
    this._interactionNotice,
    this._osc52Blocked,
    this._onExit,
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
  TerminalSettings _settings;
  late xterm.Terminal _terminal;
  late Osc8TerminalLinkTracker _osc8LinkTracker;
  final GlobalKey<xterm.TerminalViewState> _terminalViewKey =
      GlobalKey<xterm.TerminalViewState>();
  final xterm.TerminalController _terminalController = xterm.TerminalController(
    pointerInputs: const xterm.PointerInputs.all(),
  );

  /// Survives TerminalSurface dispose/rebuild so scroll position is preserved
  /// when switching tabs and coming back.
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'TerminalSession');
  final StreamController<List<int>> _ptyOutputController =
      StreamController<List<int>>();
  late final StreamSubscription<String> _decodedOutputSub;
  final StringBuffer _pendingTerminalOutput = StringBuffer();
  TerminalPtySession? _ptySession;
  StreamSubscription<TerminalPtySessionEvent>? _ptySessionSub;
  Timer? _pendingPtyResizeTimer;
  Timer? _selectionCopyTimer;
  _TerminalPtySize? _pendingPtySize;
  int _ptyGeneration = 0;
  int _startAttempt = 0;
  int? _activePtyGeneration;
  final Set<int> _exitedPtyGenerations = <int>{};
  final Set<int> _suppressedExitPtyGenerations = <int>{};
  final Set<Object> _visibilityLeases = <Object>{};

  bool _starting = false;
  bool _started = false;
  bool _running = false;
  bool _terminalOutputFlushScheduled = false;
  String _title = '';
  String? _errorMessage;
  bool _visible = false;
  bool _pendingInteractionModeReset = false;
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
    if (!settings.clipboardOnSelect) {
      _selectionCopyTimer?.cancel();
      _selectionCopyTimer = null;
    } else {
      _handleSelectionChanged();
    }
    notifyListeners();
  }

  @override
  Future<void> ensureStarted() async {
    if (_started || _starting) {
      return;
    }
    final attempt = ++_startAttempt;
    _starting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (!_isSupportedNativeDesktopTerminalPlatform) {
        throw UnsupportedError(
          'Terminal sessions require a native desktop PTY path.',
        );
      }
      final started = await _startPtySession();
      if (!_disposed && attempt == _startAttempt && started) {
        _started = true;
      }
    } catch (error) {
      if (!_disposed && attempt == _startAttempt) {
        _errorMessage = error.toString();
      }
    } finally {
      if (!_disposed && attempt == _startAttempt) {
        _starting = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> restart() async {
    _startAttempt += 1;
    _errorMessage = null;
    _started = false;
    _starting = false;
    _running = false;
    notifyListeners();
    await _stopPtySession(suppressExit: true);
    await ensureStarted();
  }

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
          launch,
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
      case TerminalPtyOutputEvent(:final data):
        if (_visible) {
          _ptyOutputController.add(data);
        }
      case TerminalPtySnapshotEvent(:final data, :final resetInteractionModes):
        _pendingInteractionModeReset |= resetInteractionModes;
        if (_visible) {
          final shouldResetInteractionModes = _pendingInteractionModeReset;
          _replaceTerminalWithSnapshot(
            data,
            resetInteractionModes: shouldResetInteractionModes,
          );
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
        ),
      );
    }
    unawaited(_stopPtySessionWithMode(suppressExit: true, terminate: false));
  }

  void _handlePrivateOsc(String code, List<String> args) {
    if (code == '52') {
      _handleOsc52(args);
      return;
    }
    _osc8LinkTracker.handlePrivateOsc(code, args);
  }

  void _handleOsc52(List<String> args) {
    final request = parseTerminalOsc52Request(args);
    if (request is! TerminalOsc52Write) {
      return;
    }
    if (!_settings.allowOsc52Clipboard) {
      _osc52Blocked();
      return;
    }
    unawaited(
      _clipboard.writeText(request.text).catchError((Object error) {
        _notifyInteraction('Could Not Copy Terminal Selection.', error: true);
      }),
    );
  }

  Future<void> _pasteFromClipboard() async {
    String? text;
    try {
      text = await _clipboard.readText();
    } catch (_) {
      // Image-only clipboards can reject text-flavor reads on some platforms.
    }
    if (_disposed) {
      return;
    }
    if (text != null && text.isNotEmpty) {
      _terminal.paste(text);
      return;
    }
    try {
      final imagePath = await _clipboard.saveImageAsTempFile();
      if (_disposed || imagePath == null || imagePath.isEmpty) {
        return;
      }
      // Shell quoting would corrupt the generated path for at least one of
      // POSIX, PowerShell, cmd, or the foreground TUI. Let the terminal apply
      // bracketed paste only when the foreground program enabled DECSET 2004.
      _terminal.paste(sanitizeTerminalImagePastePath(imagePath));
    } catch (error) {
      _notifyInteraction('Could Not Paste Clipboard Image.', error: true);
    }
  }

  void _handleSelectionChanged() {
    _selectionCopyTimer?.cancel();
    _selectionCopyTimer = null;
    if (_disposed || !_settings.clipboardOnSelect) {
      return;
    }
    final selection = _terminalController.selection;
    if (selection == null) {
      return;
    }
    _selectionCopyTimer = Timer(const Duration(milliseconds: 100), () {
      if (_disposed || !_settings.clipboardOnSelect) {
        return;
      }
      final currentSelection = _terminalController.selection;
      if (currentSelection == null) {
        return;
      }
      final text = _terminal.buffer.getText(currentSelection);
      if (text.isEmpty) {
        return;
      }
      unawaited(
        _clipboard.writeText(text).catchError((Object error) {
          _notifyInteraction('Could Not Copy Terminal Selection.', error: true);
        }),
      );
    });
  }

  void _notifyInteraction(String message, {bool error = false}) {
    _interactionNotice?.call(message, error: error);
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
    _queueTerminalOutput(data);
  }

  void _writeToTerminal(String data) {
    if (data.isEmpty || _disposed) {
      return;
    }
    _terminal.write(data);
  }

  void _queueTerminalOutput(String data) {
    if (data.isEmpty || _disposed) {
      return;
    }
    _pendingTerminalOutput.write(data);
    _scheduleTerminalOutputFlush();
  }

  void _scheduleTerminalOutputFlush() {
    if (_terminalOutputFlushScheduled || _disposed) {
      return;
    }
    _terminalOutputFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _flushPendingTerminalOutputFrame();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _flushPendingTerminalOutputFrame() {
    _terminalOutputFlushScheduled = false;
    if (_disposed) {
      _clearPendingTerminalOutput();
      return;
    }
    final pending = _pendingTerminalOutput.toString();
    if (pending.isEmpty) {
      return;
    }
    final cutoff = _terminalOutputFrameCutoff(pending);
    _clearPendingTerminalOutput();
    _writeToTerminal(pending.substring(0, cutoff));
    if (cutoff < pending.length) {
      _pendingTerminalOutput.write(pending.substring(cutoff));
      _scheduleTerminalOutputFlush();
    }
  }

  void _flushPendingTerminalOutputNow() {
    if (_disposed || _pendingTerminalOutput.isEmpty) {
      return;
    }
    final pending = _pendingTerminalOutput.toString();
    _clearPendingTerminalOutput();
    _writeToTerminal(pending);
  }

  void _clearPendingTerminalOutput() {
    _pendingTerminalOutput.clear();
  }

  void _replaceTerminalWithSnapshot(
    List<int> data, {
    required bool resetInteractionModes,
  }) {
    if (_disposed) {
      return;
    }
    _clearPendingTerminalOutput();
    _terminalController.clearSelection();
    final previousTerminal = _terminal;
    final viewWidth = previousTerminal.viewWidth;
    final viewHeight = previousTerminal.viewHeight;
    _detachTerminal(previousTerminal);
    _osc8LinkTracker.dispose();

    final nextTerminal = _createTerminal()..resize(viewWidth, viewHeight);
    _terminal = nextTerminal;
    _osc8LinkTracker = Osc8TerminalLinkTracker(terminal: nextTerminal);
    _attachTerminal(nextTerminal);
    nextTerminal.write(const Utf8Decoder(allowMalformed: true).convert(data));
    if (resetInteractionModes) {
      nextTerminal.write(terminalInteractionModeReset);
    }
    notifyListeners();
  }

  void _syncPtyOutputVisibility() {
    final session = _ptySession;
    if (_disposed || session == null) {
      return;
    }
    unawaited(
      session.setOutputPaused(!_visible).catchError((Object error) {
        _setTerminalHostError(error);
      }),
    );
  }

  void _setTerminalHostError(Object error) {
    if (_disposed) {
      return;
    }
    final message = 'Terminal host unavailable: $error';
    if (_errorMessage == message && !_running) {
      return;
    }
    _errorMessage = message;
    _running = false;
    notifyListeners();
  }

  void _syncVisibilityFromLeases() {
    final visible = _visibilityLeases.isNotEmpty;
    if (_visible == visible) {
      return;
    }
    _visible = visible;
    _syncPtyOutputVisibility();
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
  void dispose({bool terminatePty = true}) {
    _disposed = true;
    _startAttempt += 1;
    _visibilityLeases.clear();
    _visible = false;
    _osc8LinkTracker.dispose();
    _terminalController.removeListener(_handleSelectionChanged);
    _terminalController.dispose();
    _detachTerminal(_terminal);
    _clearPendingTerminalOutput();
    unawaited(
      _stopPtySessionWithMode(suppressExit: true, terminate: terminatePty),
    );
    unawaited(_decodedOutputSub.cancel());
    unawaited(_ptyOutputController.close());
    _scrollController.dispose();
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

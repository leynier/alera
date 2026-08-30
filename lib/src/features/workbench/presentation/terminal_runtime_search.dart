part of 'terminal_runtime.dart';

mixin _TerminalSearchSessionSupport on TerminalSessionHandle {
  xterm.Terminal get _terminal;

  ScrollController get _scrollController;

  FocusNode get _focusNode;

  GlobalKey<xterm.TerminalViewState> get _terminalViewKey;

  xterm.TerminalController get _terminalController;

  void _handleSelectionChanged();

  void _detachTerminal(xterm.Terminal terminal);

  void _clearPendingTerminalOutput();

  Future<void> _stopPtySessionWithMode({
    required bool suppressExit,
    required bool terminate,
  });

  StreamSubscription<String> get _decodedOutputSub;

  StreamController<List<int>> get _ptyOutputController;

  ValueNotifier<String> get _titleNotifier;

  ValueNotifier<TerminalPulseState> get _terminalPulseNotifier;

  ValueNotifier<TerminalRestoreProgress?> get _restoreProgress;

  Set<Object> get _visibilityLeases;

  Set<Object> get _retentionLeases;

  set _visible(bool value);

  set _appForeground(bool value);

  bool get _disposed;
  set _disposed(bool value);

  int get _startAttempt;
  set _startAttempt(int value);

  int get _outputVisibilityGeneration;
  set _outputVisibilityGeneration(int value);

  set _pointerInputResumePending(bool value);

  set _pointerInputCatchUpChars(int value);

  late final TerminalSearchController _searchController =
      TerminalSearchController(
        terminal: _terminal,
        scrollToLine: _scrollToSearchLine,
      );

  @override
  TerminalSearchController get searchController => _searchController;

  @override
  void openSearch() {
    if (_disposed) {
      return;
    }
    _searchController.open();
    notifyListeners();
  }

  @override
  void closeSearch() {
    if (_disposed) {
      return;
    }
    _searchController.close();
    notifyListeners();
  }

  @override
  void dispose({bool terminatePty = true}) {
    _disposed = true;
    _startAttempt += 1;
    _outputVisibilityGeneration += 1;
    _visibilityLeases.clear();
    _retentionLeases.clear();
    _visible = false;
    _appForeground = false;
    _pointerInputResumePending = false;
    _pointerInputCatchUpChars = 0;
    _searchController.dispose();
    _terminalController.removeListener(_handleSelectionChanged);
    _terminalController.dispose();
    _detachTerminal(_terminal);
    _terminal.dispose();
    _clearPendingTerminalOutput();
    unawaited(
      _stopPtySessionWithMode(suppressExit: true, terminate: terminatePty),
    );
    unawaited(_decodedOutputSub.cancel());
    unawaited(_ptyOutputController.close());
    _scrollController.dispose();
    _focusNode.dispose();
    _titleNotifier.dispose();
    _terminalPulseNotifier.dispose();
    _restoreProgress.dispose();
    composerController.dispose();
    super.dispose();
  }

  void _scrollToSearchLine(int lineIndex) {
    if (_disposed || !_scrollController.hasClients) {
      return;
    }
    final renderTerminal = _terminalViewKey.currentState?.renderTerminal;
    if (renderTerminal == null || !renderTerminal.attached) {
      return;
    }
    final lineHeight = renderTerminal.lineHeight;
    if (!lineHeight.isFinite || lineHeight <= 0) {
      return;
    }
    final position = _scrollController.position;
    final target = (lineIndex * lineHeight).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(target.toDouble());
  }
}

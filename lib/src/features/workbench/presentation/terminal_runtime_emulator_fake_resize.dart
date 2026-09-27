part of 'terminal_runtime.dart';

mixin _TerminalEmulatorFakeResizeSupport on TerminalSessionHandle {
  xterm.Terminal get _terminal;

  GlobalKey<xterm.TerminalViewState> get _terminalViewKey;

  TerminalPtySession? get _ptySession;

  _TerminalPtySize? get _lastMeasuredPtySize;

  void _flushPendingPtyResize();

  bool get _disposed;

  /// Pulses the PTY viewport and the mounted emulator, then repaints.
  ///
  /// Handles without a measured view or a live PTY do nothing. Neither pulse
  /// changes the visible layout or the final PTY dimensions.
  @override
  Future<void> refreshRendering() async {
    final size = _lastMeasuredPtySize;
    if (!_refreshEmulatorRendering() || size == null) {
      return;
    }
    _flushPendingPtyResize();
    await _ptySession?.refreshViewport(
      size.cols,
      size.rows,
      size.cellWidthPx,
      size.cellHeightPx,
    );
  }

  bool _refreshEmulatorRendering() {
    if (_disposed || _ptySession == null) {
      return false;
    }
    final viewState = _terminalViewKey.currentState;
    if (viewState == null) {
      return false;
    }
    final renderTerminal = viewState.renderTerminal;
    if (!renderTerminal.attached ||
        !renderTerminal.hasSize ||
        renderTerminal.size.isEmpty) {
      return false;
    }
    final size = _lastMeasuredPtySize;
    if (size == null ||
        size.cols <= 0 ||
        size.rows <= 0 ||
        size.cols != _terminal.viewWidth ||
        size.rows != _terminal.viewHeight) {
      return false;
    }
    _applyTerminalEmulatorFakeResize(_terminal);
    if (_disposed ||
        !identical(_terminalViewKey.currentState, viewState) ||
        !renderTerminal.attached) {
      return false;
    }
    renderTerminal.markNeedsLayout();
    renderTerminal.markNeedsPaint();
    return true;
  }
}

/// Resizes [terminal] through the fake-resize pulse with `onResize` detached.
///
/// Detaching `onResize` is what keeps the PTY at its current size: the
/// session handle's resize callback would otherwise debounce a real ioctl.
void _applyTerminalEmulatorFakeResize(xterm.Terminal terminal) {
  final onResize = terminal.onResize;
  terminal.onResize = null;
  try {
    pulseTerminalEmulatorSize(
      cols: terminal.viewWidth,
      rows: terminal.viewHeight,
      resize: (cols, rows) => terminal.resize(cols, rows),
    );
  } finally {
    terminal.onResize = onResize;
  }
}

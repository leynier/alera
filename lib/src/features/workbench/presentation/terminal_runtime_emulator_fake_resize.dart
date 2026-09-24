part of 'terminal_runtime.dart';

mixin _TerminalEmulatorFakeResizeSupport on TerminalSessionHandle {
  xterm.Terminal get _terminal;

  GlobalKey<xterm.TerminalViewState> get _terminalViewKey;

  TerminalPtySession? get _ptySession;

  bool get _disposed;

  /// Bumps the mounted emulator by about 30% and restores it, then repaints.
  ///
  /// Handles without a measured view or a live PTY do nothing. Refreshing must
  /// never replace the emulator, never replace the PTY session, and never
  /// change PTY dimensions.
  @override
  Future<void> refreshRendering() async {
    if (_disposed || _ptySession == null) {
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
    _applyTerminalEmulatorFakeResize(_terminal);
    if (_disposed ||
        !identical(_terminalViewKey.currentState, viewState) ||
        !renderTerminal.attached) {
      return;
    }
    renderTerminal.markNeedsLayout();
    renderTerminal.markNeedsPaint();
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

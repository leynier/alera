part of 'terminal_runtime.dart';

/// Visibility tracking and buffer-cost estimation for a session handle.
///
/// Both feed the memory budget: visibility is what makes a terminal an
/// eviction candidate, and the estimate is what decides whether it has to go.
extension _TerminalBufferAccounting on _XtermTerminalSessionHandle {
  void _syncVisibilityFromLeases() {
    final visible = _visibilityLeases.isNotEmpty;
    if (_visible == visible) {
      return;
    }
    _visible = visible;
    if (visible) {
      _lastVisibleAt = DateTime.now();
    }
    _syncPtyOutputVisibility();
    if (visible) {
      // Whatever arrived while hidden was queued without a frame callback.
      _scheduleTerminalOutputFlush();
    }
    _onVisibilityChanged(this);
  }

  TerminalBufferUsage _estimateBufferUsage() {
    return TerminalBufferUsage(
      tabId: tabId,
      bytes: estimateTerminalBufferBytes(
        lines: _terminal.buffer.lines.length,
        columns: _terminal.viewWidth,
      ),
      lastVisibleAt: _lastVisibleAt,
    );
  }
}

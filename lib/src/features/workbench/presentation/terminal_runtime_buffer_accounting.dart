part of 'terminal_runtime.dart';

/// Visibility tracking and buffer-cost estimation for a session handle.
///
/// Both feed the memory budget: visibility is what makes a terminal an
/// eviction candidate, and the estimate is what decides whether it has to go.
extension _TerminalBufferAccounting on _XtermTerminalSessionHandle {
  TerminalVisibilityLease _acquireVisibilityLease() {
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

  void setAppForeground(bool foreground) {
    if (_disposed || _appForeground == foreground) {
      return;
    }
    _appForeground = foreground;
    _syncPtyOutputVisibility();
    if (_outputVisible) {
      _scheduleTerminalOutputFlush();
    } else {
      _output.cancelDeferredFlush();
    }
  }

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
      bytes: measureTerminalCellBufferBytes(_terminal),
      lastVisibleAt: _lastVisibleAt,
    );
  }
}

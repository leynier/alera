part of 'terminal_runtime.dart';

/// Visible or retained handles cannot be evicted by the buffer budget.
extension _TerminalBufferAccounting on _XtermTerminalSessionHandle {
  TerminalRetentionLease _acquireRetentionLease() {
    if (_disposed) return const NoopTerminalRetentionLease();
    final token = Object();
    _retentionLeases.add(token);
    return _TerminalRetentionLease(() {
      if (_disposed || !_retentionLeases.remove(token)) return;
      _onEvictionEligibilityChanged(this);
    });
  }

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
    _onEvictionEligibilityChanged(this);
  }

  TerminalBufferUsage _estimateBufferUsage() {
    return TerminalBufferUsage(
      tabId: tabId,
      bytes: measureTerminalCellBufferBytes(_terminal),
      lastVisibleAt: _lastVisibleAt,
    );
  }
}

final class _TerminalRetentionLease implements TerminalRetentionLease {
  _TerminalRetentionLease(this._release);
  VoidCallback? _release;

  @override
  void dispose() {
    final release = _release;
    _release = null;
    release?.call();
  }
}

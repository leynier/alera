part of 'terminal_tab_view.dart';

extension _TerminalTabRefresh on _TerminalTabViewState {
  void _syncRefreshVisibility() {
    final visible = TickerMode.valuesOf(context).enabled;
    if (_entryVisible == visible) return;
    _entryVisible = visible;
    _resetEntryRefresh();
    _scheduleEntryRefresh();
  }

  void _resetEntryRefresh({bool resetViewport = false}) {
    _refreshEpoch++;
    _entryRefreshPending = true;
    _entryRefreshScheduled = false;
    if (resetViewport) {
      _viewportEpoch++;
      _pendingViewportResizes = 0;
      _refreshing = false;
    }
  }

  Future<void> _resizeViewport(int cols, int rows) async {
    final epoch = _viewportEpoch;
    _pendingViewportResizes++;
    try {
      await ref.read(_sessionProvider.notifier).resize(cols, rows);
    } catch (error, stackTrace) {
      Logger('TerminalTabView')
          .warning('terminal viewport resize failed', error, stackTrace);
    } finally {
      if (mounted && epoch == _viewportEpoch) {
        _pendingViewportResizes--;
        _scheduleEntryRefresh();
      }
    }
  }

  bool get _canRefreshEntry =>
      mounted &&
      _entryVisible &&
      _entryRefreshPending &&
      !_refreshing &&
      _pendingViewportResizes == 0 &&
      (_surfaceKey.currentState?.hasMeasuredViewport ?? false);

  void _scheduleEntryRefresh() {
    if (_entryRefreshScheduled || !_canRefreshEntry) return;
    _entryRefreshScheduled = true;
    final epoch = _refreshEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _refreshEpoch) return;
      _entryRefreshScheduled = false;
      if (!_canRefreshEntry) return;
      _entryRefreshPending = false;
      unawaited(_refreshTerminal());
    });
    // Resize acknowledgements can arrive while the frame pipeline is idle.
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _refreshTerminal() async {
    if (_refreshing) return;
    final epoch = _refreshEpoch;
    final viewportEpoch = _viewportEpoch;
    final surface = _surfaceKey.currentState;
    if (surface?.hasMeasuredViewport ?? false) {
      _entryRefreshPending = false;
    }
    _setRefreshing(true);
    try {
      await ref.read(_sessionProvider.notifier).refreshViewport();
      if (mounted &&
          epoch == _refreshEpoch &&
          identical(_surfaceKey.currentState, surface)) {
        await surface?.refreshRendering();
      }
    } catch (error, stackTrace) {
      Logger('TerminalTabView')
          .warning('terminal refresh failed', error, stackTrace);
      if (mounted && epoch == _refreshEpoch && _entryVisible) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not refresh terminal')),
        );
      }
    } finally {
      if (mounted && viewportEpoch == _viewportEpoch) {
        _setRefreshing(false);
        _scheduleEntryRefresh();
      }
    }
  }
}

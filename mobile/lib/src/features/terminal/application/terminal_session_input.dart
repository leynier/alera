part of 'terminal_session_controller.dart';

extension TerminalSessionInput on TerminalSessionController {
  /// Raw accessory/direct keys are never pasted or deferred.
  Future<void> write(List<int> bytes) => _runAttachedOperation(
    (client, sessionId) => client.writeTerminal(sessionId, bytes),
  );

  /// Explicit paste never submits and brackets only when the text needs it.
  Future<void> pasteText(String text) => _runAttachedOperation((client, id) {
    final delivery = TerminalComposeDelivery.forText(
      text,
      withEnter: false,
      hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
    );
    return client.writeTerminal(
      id,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
    );
  });

  /// Compose send separates prompt bytes from Enter when the host supports it.
  Future<void> sendComposedText(String text, {required bool withEnter}) =>
      _runAttachedOperation((client, id) {
        final delivery = TerminalComposeDelivery.forText(
          text,
          withEnter: withEnter,
          hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
        );
        return client.writeTerminal(
          id,
          delivery.bytes,
          bracketedPaste: delivery.bracketedPaste,
          deferredEnter: delivery.deferredEnter,
        );
      });

  Future<void> resize(int cols, int rows) async {
    if (cols <= 0 || rows <= 0) {
      return;
    }
    _cols = cols;
    _rows = rows;
    final shouldPulseNow = _pulseAfterLayout;
    _pulseAfterLayout = false;
    await _runAttachedOperation(
      (client, sessionId) => client.resizeTerminal(sessionId, cols, rows),
    );
    if (shouldPulseNow) {
      await refreshViewport();
      return;
    }
    _scheduleViewportPulse();
  }

  /// Briefly applies an adjacent PTY size before restoring the measured size.
  ///
  /// This forces full-screen agent TUIs to redraw without changing the Flutter
  /// view or replacing the emulator. Same pulse as desktop `refreshViewport`.
  Future<void> refreshViewport() async {
    _viewportPulseTimer?.cancel();
    _viewportPulseTimer = null;
    if (!_canPulseViewport) {
      return;
    }
    final cols = _cols;
    final rows = _rows;
    if (cols == null || rows == null || cols <= 0 || rows <= 0) {
      return;
    }
    final pulse = terminalViewportPulseSize(cols, rows);
    try {
      await _runAttachedOperation((client, sessionId) async {
        try {
          await client.resizeTerminal(sessionId, pulse.$1, pulse.$2);
        } finally {
          final restoreCols = _cols;
          final restoreRows = _rows;
          if (restoreCols != null &&
              restoreRows != null &&
              restoreCols > 0 &&
              restoreRows > 0) {
            await client.resizeTerminal(sessionId, restoreCols, restoreRows);
          }
        }
      });
      _lastPulsedSize = (cols, rows);
    } on Object catch (error, stackTrace) {
      _logger.warning('terminal viewport pulse failed', error, stackTrace);
    }
  }

  void _scheduleViewportPulse() {
    _viewportPulseTimer?.cancel();
    final pendingCols = _cols;
    final pendingRows = _rows;
    if (pendingCols == null || pendingRows == null) {
      _viewportPulseTimer = null;
      return;
    }
    final pending = (pendingCols, pendingRows);
    if (pending == _lastPulsedSize) {
      _viewportPulseTimer = null;
      return;
    }
    _viewportPulseTimer = Timer(terminalViewportPulseDebounce, () {
      _viewportPulseTimer = null;
      if (_disposed || pending != (_cols, _rows)) {
        return;
      }
      unawaited(refreshViewport());
    });
  }
}

part of 'terminal_runtime.dart';

/// Restore-progress bookkeeping for a session handle.
///
/// A restored snapshot is drained over several frames, so the surface needs
/// to know how far along it is to show something better than an empty
/// terminal.
extension _TerminalRestoreProgressTracking on _XtermTerminalSessionHandle {
  void _beginRestore(int totalChars) {
    _restoreTotalChars = totalChars;
    _restoreWrittenChars = 0;
    _restoreProgress.value = totalChars <= 0
        ? null
        : TerminalRestoreProgress(writtenChars: 0, totalChars: totalChars);
  }

  void _advanceRestore(int chars) {
    if (_restoreTotalChars <= 0) {
      return;
    }
    _restoreWrittenChars += chars;
    if (_restoreWrittenChars >= _restoreTotalChars) {
      _finishRestore();
      return;
    }
    _restoreProgress.value = TerminalRestoreProgress(
      writtenChars: _restoreWrittenChars,
      totalChars: _restoreTotalChars,
    );
  }

  /// Takes the restore overlay down.
  ///
  /// Any path that empties the backlog without going through [_advanceRestore]
  /// has to call this, or the overlay covers the terminal for good: nothing
  /// else clears it short of another snapshot or disposal.
  void _finishRestore() {
    if (_restoreTotalChars <= 0) {
      return;
    }
    _restoreTotalChars = 0;
    _restoreWrittenChars = 0;
    _restoreProgress.value = null;
  }

  void _rebuildTerminalFromSnapshot(
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
    // Scrollback can reach the host's 10 MB cap, and parsing all of it in one
    // synchronous write blocked the frame that showed the terminal. Go through
    // the same per-frame batcher as live output instead.
    final restored = const Utf8Decoder(allowMalformed: true).convert(data);
    _beginRestore(restored.length);
    _queueTerminalOutput(restored, source: _TerminalOutputSource.restore);
    if (resetInteractionModes) {
      _queueTerminalOutput(
        terminalInteractionModeReset,
        source: _TerminalOutputSource.control,
      );
    }
  }
}

part of 'terminal_runtime.dart';

/// Keeps pointer events behind the output that determines terminal mouse mode.
///
/// A hidden terminal can leave the emulator in a TUI mouse mode while the host
/// has already returned to the shell. The missed cleanup bytes arrive during
/// resume, so clicks stay suspended until that prefix has been parsed.
extension _TerminalPointerSynchronization on _XtermTerminalSessionHandle {
  void _syncPtyOutputVisibility() {
    final generation = ++_outputVisibilityGeneration;
    final session = _ptySession;
    if (_disposed || session == null) {
      _pointerInputResumePending = false;
      _refreshPointerInputSuspension();
      return;
    }

    final paused = !_outputVisible;
    _pointerInputResumePending = !paused;
    _refreshPointerInputSuspension();
    unawaited(
      _applyPtyOutputVisibility(
        session: session,
        paused: paused,
        generation: generation,
      ),
    );
  }

  Future<void> _applyPtyOutputVisibility({
    required TerminalPtySession session,
    required bool paused,
    required int generation,
  }) async {
    try {
      await session.setOutputPaused(paused);
    } catch (error) {
      if (!_disposed &&
          identical(_ptySession, session) &&
          generation == _outputVisibilityGeneration) {
        _setTerminalHostError(error);
      }
      return;
    }
    if (_disposed ||
        paused ||
        !_outputVisible ||
        !identical(_ptySession, session) ||
        generation != _outputVisibilityGeneration) {
      return;
    }
    _schedulePointerInputResume(generation);
  }

  void _schedulePointerInputResume(int generation) {
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (_disposed ||
          !_outputVisible ||
          generation != _outputVisibilityGeneration) {
        return;
      }
      _pointerInputResumePending = false;
      if (_output.length > _pointerInputCatchUpChars) {
        _pointerInputCatchUpChars = _output.length;
      }
      _refreshPointerInputSuspension();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _preparePointerInputForSnapshot() {
    _pointerInputCatchUpChars = 0;
    _setPointerInputSuspended(true);
  }

  void _completePointerInputSnapshotCatchUp() {
    _pointerInputCatchUpChars = _output.length;
    _refreshPointerInputSuspension();
  }

  void _advancePointerInputCatchUp(int chars) {
    if (chars <= 0 || _pointerInputCatchUpChars <= 0) {
      return;
    }
    if (chars >= _pointerInputCatchUpChars) {
      _pointerInputCatchUpChars = 0;
    } else {
      _pointerInputCatchUpChars -= chars;
    }
    _refreshPointerInputSuspension();
  }

  void _discardPointerInputCatchUp({required int offset, required int chars}) {
    if (chars <= 0 || offset >= _pointerInputCatchUpChars) {
      return;
    }
    final prefixRemaining = _pointerInputCatchUpChars - offset;
    _advancePointerInputCatchUp(
      chars < prefixRemaining ? chars : prefixRemaining,
    );
  }

  void _resetPointerInputSynchronization() {
    _outputVisibilityGeneration += 1;
    _pointerInputResumePending = false;
    _pointerInputCatchUpChars = 0;
    _refreshPointerInputSuspension();
  }

  void _refreshPointerInputSuspension() {
    _setPointerInputSuspended(
      !_outputVisible ||
          _pointerInputResumePending ||
          _pointerInputCatchUpChars > 0,
    );
  }

  void _setPointerInputSuspended(bool suspended) {
    if (_terminalController.suspendedPointerInputs == suspended) {
      return;
    }
    _terminalController.setSuspendPointerInput(suspended);
  }
}

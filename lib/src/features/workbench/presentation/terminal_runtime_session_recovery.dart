part of 'terminal_runtime.dart';

extension _TerminalRecoveryState on _XtermTerminalSessionHandle {
  void _setTerminalHostError(Object error) {
    if (_disposed) {
      return;
    }
    final message = 'Terminal host unavailable: $error';
    if (_errorMessage == message) {
      return;
    }
    _errorMessage = message;
    _notifySessionListeners();
  }
}

Future<void> _ensureTerminalSessionStarted(
  _XtermTerminalSessionHandle handle,
) async {
  if (handle._started || handle._starting) {
    return;
  }
  final attempt = ++handle._startAttempt;
  handle._starting = true;
  handle._operation = TerminalSessionOperation.starting;
  handle._errorMessage = null;
  handle._notifySessionListeners();
  try {
    if (!_isSupportedNativeDesktopTerminalPlatform) {
      throw UnsupportedError(
        'Terminal sessions require a native desktop PTY path.',
      );
    }
    final started = await handle._startPtySession();
    if (!handle._disposed && attempt == handle._startAttempt && started) {
      handle._started = true;
    }
  } catch (error) {
    if (!handle._disposed && attempt == handle._startAttempt) {
      handle._errorMessage = error.toString();
    }
  } finally {
    if (!handle._disposed && attempt == handle._startAttempt) {
      handle._starting = false;
      handle._operation = null;
      handle._notifySessionListeners();
    }
  }
}

Future<void> _reconnectTerminalSession(
  _XtermTerminalSessionHandle handle,
) async {
  final session = handle._ptySession;
  if (session is! RecoverableTerminalPtySession) {
    await _restartTerminalSession(handle);
    return;
  }
  await _recoverTerminalSession(
    handle,
    operation: TerminalSessionOperation.reconnecting,
    recover: session.reconnect,
  );
}

Future<void> _restartTerminalSession(_XtermTerminalSessionHandle handle) async {
  handle._markTerminalPulseDisarmed();
  final session = handle._ptySession;
  if (session is RecoverableTerminalPtySession && session.supportsRestart) {
    await _recoverTerminalSession(
      handle,
      operation: TerminalSessionOperation.restarting,
      clearExitedGeneration: true,
      recover: () async {
        await session.restartProcess();
        if (!handle._disposed) {
          handle._resetPointerInputSynchronization();
        }
      },
    );
    return;
  }
  handle._startAttempt += 1;
  handle._errorMessage = null;
  handle._started = false;
  handle._starting = false;
  handle._operation = TerminalSessionOperation.restarting;
  handle._running = false;
  handle._notifySessionListeners();
  await handle._stopPtySession(suppressExit: true);
  handle._resetPointerInputSynchronization();
  if (handle._disposed) {
    return;
  }
  handle._operation = null;
  await _ensureTerminalSessionStarted(handle);
}

Future<void> _recoverTerminalSession(
  _XtermTerminalSessionHandle handle, {
  required TerminalSessionOperation operation,
  bool clearExitedGeneration = false,
  required Future<void> Function() recover,
}) async {
  if (handle._disposed || handle._operation != null) {
    return;
  }
  handle._errorMessage = null;
  handle._operation = operation;
  handle._starting = true;
  handle._notifySessionListeners();
  final generationBeforeRecovery = handle._activePtyGeneration;
  final restoredExitedGeneration =
      clearExitedGeneration &&
      generationBeforeRecovery != null &&
      handle._exitedPtyGenerations.remove(generationBeforeRecovery);
  try {
    await recover();
    if (!handle._disposed) {
      final generation = handle._activePtyGeneration;
      final pulseSession = handle._ptySession;
      if (pulseSession == null) {
        handle._markTerminalPulseDisarmed();
      } else {
        await handle._refreshTerminalPulseState(
          pulseSession,
          isCurrent: () =>
              !handle._disposed &&
              generation != null &&
              handle._activePtyGeneration == generation &&
              identical(handle._ptySession, pulseSession),
        );
      }
      handle._running =
          generation != null &&
          handle._activePtyGeneration == generation &&
          identical(handle._ptySession, pulseSession) &&
          !handle._exitedPtyGenerations.contains(generation);
    }
  } catch (error) {
    if (!handle._disposed) {
      if (restoredExitedGeneration &&
          handle._activePtyGeneration == generationBeforeRecovery) {
        handle._exitedPtyGenerations.add(generationBeforeRecovery);
      }
      handle._errorMessage = 'Terminal host unavailable: $error';
    }
  } finally {
    if (!handle._disposed) {
      handle._starting = false;
      handle._operation = null;
      handle._notifySessionListeners();
    }
  }
}

part of 'terminal_runtime.dart';

bool _submitTerminalText(_XtermTerminalSessionHandle handle, String text) {
  final session = handle._ptySession;
  if (handle._disposed || session == null) {
    return false;
  }

  if (session is DeferredEnterTerminalPtySession &&
      session.supportsDeferredEnter) {
    final bytes = buildTerminalSubmitPayloadBytes(
      text,
      bracketedPasteMode: handle._terminal.bracketedPasteMode,
    );
    return session.writeBytesWithDeferredEnter(bytes);
  }

  _pasteTerminalText(handle, text);
  _cancelDeferredSubmitEnter(handle);
  handle._deferredSubmitEnterTimer = Timer(terminalAgentPromptSubmitDelay, () {
    handle._deferredSubmitEnterTimer = null;
    if (handle._disposed || !identical(handle._ptySession, session)) {
      return;
    }
    handle._handleTerminalInput('\r');
  });
  return true;
}

void _cancelDeferredSubmitEnter(_XtermTerminalSessionHandle handle) {
  handle._deferredSubmitEnterTimer?.cancel();
  handle._deferredSubmitEnterTimer = null;
}

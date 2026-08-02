part of 'terminal_runtime.dart';

bool isSupportedNativeDesktopTerminalPlatformForTesting(
  TargetPlatform platform, {
  bool isWeb = false,
}) {
  return _isSupportedNativeDesktopTerminalPlatformFor(platform, isWeb: isWeb);
}

@visibleForTesting
xterm.TerminalTargetPlatform xtermTargetPlatformForTesting(
  TargetPlatform platform,
) {
  return _xtermTargetPlatformFor(platform);
}

@visibleForTesting
String resolveTerminalFontFamilyForTesting(String fontFamily) {
  return _resolveTerminalFontFamily(fontFamily);
}

@visibleForTesting
Set<int>? wordSeparatorsFromSettingsForTesting(String? value) {
  return _wordSeparatorsFromSettings(value);
}

@visibleForTesting
xterm.TerminalCursorType xtermCursorTypeForTesting(TerminalCursorShape shape) {
  return shape.toXtermCursorType();
}

@visibleForTesting
Color? colorFromHexForTesting(String? value) {
  return _colorFromHex(value);
}

@visibleForTesting
xterm.TerminalTheme resolveXtermThemeForTesting(TerminalSettings settings) {
  return _resolveXtermTheme(settings);
}

@visibleForTesting
void feedTerminalInputForTesting(TerminalSessionHandle session, String data) {
  (session as _XtermTerminalSessionHandle)._handleTerminalInput(data);
}

@visibleForTesting
void writeTerminalOutputForTesting(TerminalSessionHandle session, String data) {
  final handle = session as _XtermTerminalSessionHandle;
  handle._handleTerminalOutput(data);
  handle._flushPendingTerminalOutputNow();
}

@visibleForTesting
void queueTerminalOutputForTesting(TerminalSessionHandle session, String data) {
  (session as _XtermTerminalSessionHandle)._handleTerminalOutput(data);
}

@visibleForTesting
void flushTerminalOutputForTesting(TerminalSessionHandle session) {
  (session as _XtermTerminalSessionHandle)._flushPendingTerminalOutputFrame();
}

/// Whether a flush is pending, either as a frame callback or as a deferred
/// timer.
@visibleForTesting
bool terminalOutputFlushScheduledForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._output.flushScheduled;
}

/// Whether the pending flush is waiting on the cadence floor rather than on the
/// next frame.
@visibleForTesting
bool terminalOutputFlushDeferredForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._output.flushTimer != null;
}

@visibleForTesting
void forceDeferredTerminalOutputFlushForTesting(TerminalSessionHandle session) {
  final output = (session as _XtermTerminalSessionHandle)._output;
  output.flushTimer?.cancel();
  output.flushScheduled = true;
  output.flushTimer = Timer(const Duration(hours: 1), () {});
}

@visibleForTesting
int terminalOutputFlushCountForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._output.flushCount;
}

@visibleForTesting
Duration get terminalOutputMinFlushIntervalForTesting =>
    _terminalOutputMinFlushInterval;

@visibleForTesting
int terminalOutputFrameCutoffForTesting(String value) {
  return _terminalOutputChunkCutoff(value, _terminalOutputMaxCharsPerFrame);
}

@visibleForTesting
int pendingTerminalOutputCharsForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._output.length;
}

@visibleForTesting
int pendingLiveTerminalOutputCharsForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._output.liveLength;
}

@visibleForTesting
int pendingRestoreTerminalOutputCharsForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._output.restoreLength;
}

/// The head chunk itself, so a test can assert it is consumed in place rather
/// than re-queued as a fresh copy on every drain.
@visibleForTesting
String? pendingTerminalOutputHeadChunkForTesting(
  TerminalSessionHandle session,
) {
  final pending = (session as _XtermTerminalSessionHandle)._output.pending;
  return pending.isEmpty ? null : pending.first.text;
}

@visibleForTesting
int pendingTerminalOutputHeadForTesting(TerminalSessionHandle session) {
  final pending = (session as _XtermTerminalSessionHandle)._output.pending;
  return pending.isEmpty ? 0 : pending.first.head;
}

@visibleForTesting
String terminalBufferTextForTesting(TerminalSessionHandle session) {
  final terminal = (session as _XtermTerminalSessionHandle)._terminal;
  return <String>[
    for (var i = 0; i < terminal.buffer.height; i++)
      terminal.buffer.lines[i].toString(),
  ].join('\n');
}

@visibleForTesting
xterm.MouseMode terminalMouseModeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._terminal.mouseMode;
}

@visibleForTesting
bool terminalPointerInputSuspendedForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)
      ._terminalController
      .suspendedPointerInputs;
}

@visibleForTesting
bool terminalBracketedPasteModeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._terminal.bracketedPasteMode;
}

@visibleForTesting
bool terminalCursorVisibleModeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._terminal.cursorVisibleMode;
}

@visibleForTesting
bool terminalCursorKeysModeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._terminal.cursorKeysMode;
}

@visibleForTesting
bool terminalReportFocusModeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._terminal.reportFocusMode;
}

@visibleForTesting
bool terminalAppKeypadModeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._terminal.appKeypadMode;
}

@visibleForTesting
bool terminalIsUsingAltBufferForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._terminal.isUsingAltBuffer;
}

@visibleForTesting
bool terminalFocusHasFocusForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._focusNode.hasFocus;
}

@visibleForTesting
TerminalVisibilityLease acquireTerminalVisibilityForTesting(
  TerminalSessionHandle session,
) {
  return (session as _XtermTerminalSessionHandle).acquireVisibility();
}

@visibleForTesting
void setTerminalTitleForTesting(TerminalSessionHandle session, String title) {
  (session as _XtermTerminalSessionHandle)._handleTitleChanged(title);
}

@visibleForTesting
void handleTerminalResizeForTesting(
  TerminalSessionHandle session,
  int width,
  int height,
  int pixelWidth,
  int pixelHeight,
) {
  (session as _XtermTerminalSessionHandle)._handleTerminalResize(
    width,
    height,
    pixelWidth,
    pixelHeight,
  );
}

@visibleForTesting
void flushPendingPtyResizeForTesting(TerminalSessionHandle session) {
  (session as _XtermTerminalSessionHandle)._flushPendingPtyResize();
}

@visibleForTesting
void handlePrivateOscForTesting(
  TerminalSessionHandle session,
  String code,
  List<String> args,
) {
  (session as _XtermTerminalSessionHandle)._handlePrivateOsc(code, args);
}

@visibleForTesting
Future<void> pasteTerminalClipboardForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._pasteFromClipboard();
}

@visibleForTesting
void selectTerminalRangeForTesting(
  TerminalSessionHandle session,
  xterm.CellOffset start,
  xterm.CellOffset end,
) {
  final handle = session as _XtermTerminalSessionHandle;
  handle._terminalController.setSelection(
    handle._terminal.buffer.createAnchorFromOffset(start),
    handle._terminal.buffer.createAnchorFromOffset(end),
  );
}

@visibleForTesting
FocusNode terminalFocusNodeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._focusNode;
}

@visibleForTesting
void requestTerminalFocusNowForTesting(TerminalSessionHandle session) {
  (session as _XtermTerminalSessionHandle)._requestFocusNow();
}

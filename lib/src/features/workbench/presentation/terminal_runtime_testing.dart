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

@visibleForTesting
int terminalOutputFrameCutoffForTesting(String value) {
  return _terminalOutputFrameCutoff(value);
}

@visibleForTesting
int pendingTerminalOutputCharsForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._pendingTerminalOutput.length;
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

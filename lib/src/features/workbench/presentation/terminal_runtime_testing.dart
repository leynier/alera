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
  (session as _XtermTerminalSessionHandle)._handleTerminalOutput(data);
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
FocusNode terminalFocusNodeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._focusNode;
}

@visibleForTesting
void requestTerminalFocusNowForTesting(TerminalSessionHandle session) {
  (session as _XtermTerminalSessionHandle)._requestFocusNow();
}

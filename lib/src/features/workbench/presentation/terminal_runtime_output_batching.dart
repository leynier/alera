part of 'terminal_runtime.dart';

void _writeSessionTerminal(_XtermTerminalSessionHandle handle, String data) {
  if (data.isEmpty || handle._disposed) {
    return;
  }
  handle._terminal.write(data);
}

void _queueSessionTerminalOutput(
  _XtermTerminalSessionHandle handle,
  String data,
) {
  if (data.isEmpty || handle._disposed) {
    return;
  }
  handle._pendingTerminalOutput.write(data);
  handle._scheduleTerminalOutputFlush();
}

void _scheduleSessionTerminalOutputFlush(_XtermTerminalSessionHandle handle) {
  if (handle._terminalOutputFlushScheduled || handle._disposed) {
    return;
  }
  handle._terminalOutputFlushScheduled = true;
  SchedulerBinding.instance.scheduleFrameCallback((_) {
    handle._flushPendingTerminalOutputFrame();
  });
  SchedulerBinding.instance.ensureVisualUpdate();
}

void _flushSessionTerminalOutputFrame(_XtermTerminalSessionHandle handle) {
  handle._terminalOutputFlushScheduled = false;
  if (handle._disposed) {
    handle._clearPendingTerminalOutput();
    return;
  }
  final pending = handle._pendingTerminalOutput.toString();
  if (pending.isEmpty) {
    return;
  }
  final cutoff = _terminalOutputFrameCutoff(pending);
  handle._clearPendingTerminalOutput();
  handle._writeToTerminal(pending.substring(0, cutoff));
  if (cutoff < pending.length) {
    handle._pendingTerminalOutput.write(pending.substring(cutoff));
    handle._scheduleTerminalOutputFlush();
  }
}

void _flushSessionTerminalOutputNow(_XtermTerminalSessionHandle handle) {
  if (handle._disposed || handle._pendingTerminalOutput.isEmpty) {
    return;
  }
  final pending = handle._pendingTerminalOutput.toString();
  handle._clearPendingTerminalOutput();
  handle._writeToTerminal(pending);
}

int _terminalOutputFrameCutoff(String value) {
  if (value.length <= _terminalOutputMaxCharsPerFrame) {
    return value.length;
  }
  var cutoff = _terminalOutputMaxCharsPerFrame;
  final codeUnit = value.codeUnitAt(cutoff);
  if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
    cutoff -= 1;
  }
  return cutoff;
}

const int _terminalOutputMaxCharsPerFrame = 64 * 1024;

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
  var offset = 0;
  while (offset < data.length) {
    if (handle._pendingTerminalOutput.length >=
        _terminalOutputMaxPendingChars) {
      _drainSessionTerminalOutputChunk(handle);
    }
    final available =
        _terminalOutputMaxPendingChars - handle._pendingTerminalOutput.length;
    final end = (offset + available).clamp(0, data.length);
    handle._pendingTerminalOutput.write(data.substring(offset, end));
    offset = end;
  }
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
  _drainSessionTerminalOutputChunk(handle);
  if (handle._pendingTerminalOutput.isNotEmpty) {
    handle._scheduleTerminalOutputFlush();
  }
}

void _drainSessionTerminalOutputChunk(_XtermTerminalSessionHandle handle) {
  final pending = handle._pendingTerminalOutput.toString();
  if (pending.isEmpty) {
    return;
  }
  final cutoff = _terminalOutputFrameCutoff(pending);
  handle._clearPendingTerminalOutput();
  handle._writeToTerminal(pending.substring(0, cutoff));
  if (cutoff < pending.length) {
    handle._pendingTerminalOutput.write(pending.substring(cutoff));
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
const int _terminalOutputMaxPendingChars = 1024 * 1024;

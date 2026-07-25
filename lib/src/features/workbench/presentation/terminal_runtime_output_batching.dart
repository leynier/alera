part of 'terminal_runtime.dart';

void _writeSessionTerminal(_XtermTerminalSessionHandle handle, String data) {
  if (data.isEmpty || handle._disposed) {
    return;
  }
  handle._terminal.write(data);
}

void _queueSessionTerminalOutput(
  _XtermTerminalSessionHandle handle,
  String data, {
  bool bounded = true,
}) {
  if (data.isEmpty || handle._disposed) {
    return;
  }
  handle._pendingTerminalOutput.add(data);
  handle._pendingTerminalOutputLength += data.length;
  if (!bounded) {
    // A restored snapshot is a bounded one-shot payload, so it is exempt from
    // the backlog cap that exists to contain a runaway live process.
    handle._scheduleTerminalOutputFlush();
    return;
  }
  // Drop the oldest output rather than let a runaway process grow the backlog
  // without bound. Newer output is what the user is looking at.
  while (handle._pendingTerminalOutputLength > _terminalOutputMaxPendingChars &&
      handle._pendingTerminalOutput.length > 1) {
    handle._pendingTerminalOutputLength -= handle._pendingTerminalOutput
        .removeFirst()
        .length;
  }
  if (handle._pendingTerminalOutputLength > _terminalOutputMaxPendingChars) {
    // A single chunk can exceed the cap on its own, so trim its head too.
    final chunk = handle._pendingTerminalOutput.removeFirst();
    final start = _terminalOutputHeadTrimStart(
      chunk,
      chunk.length - _terminalOutputMaxPendingChars,
    );
    handle._pendingTerminalOutput.addFirst(chunk.substring(start));
    handle._pendingTerminalOutputLength = chunk.length - start;
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

/// Writes at most one frame's worth of pending output, splitting only the
/// chunk that straddles the budget so the rest stays untouched.
void _drainSessionTerminalOutputChunk(_XtermTerminalSessionHandle handle) {
  final pending = handle._pendingTerminalOutput;
  if (pending.isEmpty) {
    return;
  }
  final frame = StringBuffer();
  var written = 0;
  while (pending.isNotEmpty && written < _terminalOutputMaxCharsPerFrame) {
    final chunk = pending.first;
    final remaining = _terminalOutputMaxCharsPerFrame - written;
    if (chunk.length <= remaining) {
      pending.removeFirst();
      handle._pendingTerminalOutputLength -= chunk.length;
      frame.write(chunk);
      written += chunk.length;
      continue;
    }
    final cutoff = _terminalOutputChunkCutoff(chunk, remaining);
    if (cutoff == 0) {
      break;
    }
    pending.removeFirst();
    pending.addFirst(chunk.substring(cutoff));
    handle._pendingTerminalOutputLength -= cutoff;
    frame.write(chunk.substring(0, cutoff));
    written += cutoff;
  }
  if (written == 0) {
    return;
  }
  handle._writeToTerminal(frame.toString());
  handle._advanceRestore(written);
}

void _flushSessionTerminalOutputNow(_XtermTerminalSessionHandle handle) {
  if (handle._disposed || handle._pendingTerminalOutput.isEmpty) {
    return;
  }
  final pending = handle._pendingTerminalOutput.join();
  handle._clearPendingTerminalOutput();
  handle._writeToTerminal(pending);
}

/// Start index for a head trim that never lands inside a surrogate pair.
int _terminalOutputHeadTrimStart(String value, int start) {
  if (start <= 0) {
    return 0;
  }
  if (start >= value.length) {
    return value.length;
  }
  final codeUnit = value.codeUnitAt(start);
  if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
    return start + 1;
  }
  return start;
}

/// Never cuts between a surrogate pair, which would corrupt the code point.
int _terminalOutputChunkCutoff(String value, int limit) {
  if (value.length <= limit) {
    return value.length;
  }
  final codeUnit = value.codeUnitAt(limit);
  if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
    return limit - 1;
  }
  return limit;
}

const int _terminalOutputMaxCharsPerFrame = 64 * 1024;
const int _terminalOutputMaxPendingChars = 1024 * 1024;

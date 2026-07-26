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
    handle._pendingTerminalOutputLength -= _terminalOutputHeadRemaining(handle);
    handle._pendingTerminalOutput.removeFirst();
    handle._pendingTerminalOutputHead = 0;
  }
  if (handle._pendingTerminalOutputLength > _terminalOutputMaxPendingChars) {
    // A single chunk can exceed the cap on its own, so trim its head too.
    final chunk = handle._pendingTerminalOutput.first;
    final start = _terminalOutputHeadTrimStart(
      chunk,
      chunk.length - _terminalOutputMaxPendingChars,
    );
    handle._pendingTerminalOutputHead = start;
    handle._pendingTerminalOutputLength = chunk.length - start;
  }
  handle._scheduleTerminalOutputFlush();
}

/// Chars left in the head chunk.
int _terminalOutputHeadRemaining(_XtermTerminalSessionHandle handle) {
  return handle._pendingTerminalOutput.first.length -
      handle._pendingTerminalOutputHead;
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

/// Writes at most one frame's worth of pending output, consuming the chunk
/// that straddles the budget in place so the rest is never copied.
void _drainSessionTerminalOutputChunk(_XtermTerminalSessionHandle handle) {
  final pending = handle._pendingTerminalOutput;
  if (pending.isEmpty) {
    return;
  }
  final frame = StringBuffer();
  var written = 0;
  while (pending.isNotEmpty && written < _terminalOutputMaxCharsPerFrame) {
    final chunk = pending.first;
    final head = handle._pendingTerminalOutputHead;
    final available = chunk.length - head;
    final remaining = _terminalOutputMaxCharsPerFrame - written;
    if (available <= remaining) {
      pending.removeFirst();
      handle._pendingTerminalOutputHead = 0;
      handle._pendingTerminalOutputLength -= available;
      frame.write(head == 0 ? chunk : chunk.substring(head));
      written += available;
      continue;
    }
    // Absolute index, because the budget is measured from the head, not from
    // the start of the chunk.
    final cutoff = _terminalOutputChunkCutoff(chunk, head + remaining);
    if (cutoff <= head) {
      break;
    }
    handle._pendingTerminalOutputHead = cutoff;
    handle._pendingTerminalOutputLength -= cutoff - head;
    frame.write(chunk.substring(head, cutoff));
    written += cutoff - head;
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
  final head = handle._pendingTerminalOutputHead;
  final buffer = StringBuffer();
  var first = true;
  for (final chunk in handle._pendingTerminalOutput) {
    buffer.write(first && head > 0 ? chunk.substring(head) : chunk);
    first = false;
  }
  handle._clearPendingTerminalOutput();
  handle._writeToTerminal(buffer.toString());
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

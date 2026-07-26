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
  handle._output.pending.add(data);
  handle._output.length += data.length;
  if (!bounded) {
    // A restored snapshot is a bounded one-shot payload, so it is exempt from
    // the backlog cap that exists to contain a runaway live process.
    handle._scheduleTerminalOutputFlush();
    return;
  }
  // Drop the oldest output rather than let a runaway process grow the backlog
  // without bound. Newer output is what the user is looking at.
  while (handle._output.length > _terminalOutputMaxPendingChars &&
      handle._output.pending.length > 1) {
    handle._output.length -= handle._output.headRemaining;
    handle._output.pending.removeFirst();
    handle._output.head = 0;
  }
  if (handle._output.length > _terminalOutputMaxPendingChars) {
    // A single chunk can exceed the cap on its own, so trim its head too.
    final chunk = handle._output.pending.first;
    final start = _terminalOutputHeadTrimStart(
      chunk,
      chunk.length - _terminalOutputMaxPendingChars,
    );
    handle._output.head = start;
    handle._output.length = chunk.length - start;
  }
  handle._scheduleTerminalOutputFlush();
}

void _scheduleSessionTerminalOutputFlush(_XtermTerminalSessionHandle handle) {
  // A hidden terminal keeps its backlog but pays no frame time for it; the
  // backlog is drained when it becomes visible again.
  if (handle._output.flushScheduled || handle._disposed || !handle._visible) {
    return;
  }
  final clock = handle._output.sinceFlushRequest;
  // An unstarted clock means nothing has been flushed yet, so the first chunk
  // goes out on the next frame rather than waiting for a cadence it has not
  // used up.
  final sinceLastFlush = clock.isRunning
      ? clock.elapsed
      : _terminalOutputMinFlushInterval;
  if (sinceLastFlush >= _terminalOutputMinFlushInterval) {
    _requestSessionTerminalOutputFrame(handle);
    return;
  }
  handle._output.flushScheduled = true;
  handle._output.flushTimer = Timer(
    _terminalOutputMinFlushInterval - sinceLastFlush,
    () {
      handle._output.flushTimer = null;
      handle._output.flushScheduled = false;
      if (handle._disposed || !handle._visible) {
        return;
      }
      _requestSessionTerminalOutputFrame(handle);
    },
  );
}

void _requestSessionTerminalOutputFrame(_XtermTerminalSessionHandle handle) {
  handle._output.flushScheduled = true;
  // The cadence is measured from here rather than from the flush that follows,
  // because the frame callback lands up to a vsync later: charging that wait to
  // the next interval as well would pace the terminal at 20 Hz, not 30.
  handle._output.restartFlushClock();
  SchedulerBinding.instance.scheduleFrameCallback((_) {
    handle._flushPendingTerminalOutputFrame();
  });
  SchedulerBinding.instance.ensureVisualUpdate();
}

void _flushSessionTerminalOutputFrame(_XtermTerminalSessionHandle handle) {
  handle._output.flushScheduled = false;
  handle._output.flushCount += 1;
  if (handle._disposed) {
    handle._clearPendingTerminalOutput();
    return;
  }
  _drainSessionTerminalOutputChunk(handle);
  if (handle._output.pending.isNotEmpty) {
    handle._scheduleTerminalOutputFlush();
  }
}

/// Writes at most one frame's worth of pending output, consuming the chunk
/// that straddles the budget in place so the rest is never copied.
void _drainSessionTerminalOutputChunk(_XtermTerminalSessionHandle handle) {
  final pending = handle._output.pending;
  if (pending.isEmpty) {
    return;
  }
  final frame = StringBuffer();
  var written = 0;
  while (pending.isNotEmpty && written < _terminalOutputMaxCharsPerFrame) {
    final chunk = pending.first;
    final head = handle._output.head;
    final available = chunk.length - head;
    final remaining = _terminalOutputMaxCharsPerFrame - written;
    if (available <= remaining) {
      pending.removeFirst();
      handle._output.head = 0;
      handle._output.length -= available;
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
    handle._output.head = cutoff;
    handle._output.length -= cutoff - head;
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
  handle._output.cancelDeferredFlush();
  if (handle._disposed || handle._output.pending.isEmpty) {
    return;
  }
  handle._output.restartFlushClock();
  final head = handle._output.head;
  final buffer = StringBuffer();
  var first = true;
  for (final chunk in handle._output.pending) {
    buffer.write(first && head > 0 ? chunk.substring(head) : chunk);
    first = false;
  }
  handle._clearPendingTerminalOutput();
  handle._writeToTerminal(buffer.toString());
  // Everything queued is on screen now, including a restore this bypassed.
  handle._finishRestore();
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

/// Floor on the gap between two flushes, so a process writing without pause
/// cannot drive the frame loop at full vsync.
///
/// Measured on Linux: a frame costs roughly the same whether it changes one
/// line or a whole screen, because the fixed per-frame cost dominates - the GTK
/// embedder reads the rendered surface back and composites it in software on
/// the platform thread (`gdk_cairo_draw_from_gl`), which no GDK setting avoids.
/// CPU therefore tracks the frame count almost linearly: 30 fps of streaming
/// output cost 48% of a core against 31% at 20 fps, with a bare frame costing
/// ~6 ms of CPU on its own. Nobody reads text scrolling at 60 Hz, so the cap
/// buys back that difference with no visible loss.
///
/// This is a floor on cadence, not a delay on arrival: a terminal that has been
/// quiet flushes on the very next frame, so echo latency while typing is
/// unchanged.
const Duration _terminalOutputMinFlushInterval = Duration(milliseconds: 33);

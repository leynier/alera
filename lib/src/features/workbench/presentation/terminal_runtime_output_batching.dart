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
  _TerminalOutputSource source = _TerminalOutputSource.live,
}) {
  if (data.isEmpty || handle._disposed) {
    return;
  }
  handle._output.add(_TerminalOutputSegment(data, source));
  if (source == _TerminalOutputSource.live) {
    _trimSessionLiveOutputBacklog(handle);
  }
  handle._scheduleTerminalOutputFlush();
}

void _trimSessionLiveOutputBacklog(_XtermTerminalSessionHandle handle) {
  final output = handle._output;
  // Preserve the snapshot and its mode reset. Only old live output is
  // expendable, even when it sits behind a multi-megabyte restore segment.
  while (output.liveLength > _terminalOutputMaxPendingChars) {
    final segment = output.pending.firstWhere(
      (candidate) => candidate.source == _TerminalOutputSource.live,
    );
    final offset = output.offsetOf(segment);
    final excess = output.liveLength - _terminalOutputMaxPendingChars;
    final trim = excess < segment.remaining ? excess : segment.remaining;
    final target = segment.head + trim;
    final nextHead = _terminalOutputHeadTrimStart(segment.text, target);
    final dropped = nextHead - segment.head;
    output.consume(segment, dropped);
    handle._discardPointerInputCatchUp(offset: offset, chars: dropped);
  }
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
  var restoreWritten = 0;
  while (pending.isNotEmpty && written < _terminalOutputMaxCharsPerFrame) {
    final segment = pending.first;
    final head = segment.head;
    final available = segment.remaining;
    final remaining = _terminalOutputMaxCharsPerFrame - written;
    if (available <= remaining) {
      frame.write(segment.remainingText);
      handle._output.consume(segment, available);
      written += available;
      if (segment.source == _TerminalOutputSource.restore) {
        restoreWritten += available;
      }
      continue;
    }
    // Absolute index, because the budget is measured from the head, not from
    // the start of the chunk.
    final cutoff = _terminalOutputChunkCutoff(segment.text, head + remaining);
    if (cutoff <= head) {
      break;
    }
    final consumed = cutoff - head;
    frame.write(segment.text.substring(head, cutoff));
    handle._output.consume(segment, consumed);
    written += consumed;
    if (segment.source == _TerminalOutputSource.restore) {
      restoreWritten += consumed;
    }
  }
  if (written == 0) {
    return;
  }
  handle._writeToTerminal(frame.toString());
  handle._advanceRestore(restoreWritten);
  handle._advancePointerInputCatchUp(written);
}

void _flushSessionTerminalOutputNow(_XtermTerminalSessionHandle handle) {
  handle._output.cancelDeferredFlush();
  if (handle._disposed || handle._output.pending.isEmpty) {
    return;
  }
  handle._output.restartFlushClock();
  final pendingChars = handle._output.length;
  final buffer = StringBuffer();
  for (final segment in handle._output.pending) {
    buffer.write(segment.remainingText);
  }
  handle._clearPendingTerminalOutput();
  handle._writeToTerminal(buffer.toString());
  // Everything queued is on screen now, including a restore this bypassed.
  handle._finishRestore();
  handle._advancePointerInputCatchUp(pendingChars);
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

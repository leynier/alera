part of 'terminal_runtime.dart';

enum _TerminalOutputSource { restore, control, live }

class _TerminalOutputSegment(
  final String text,
  final _TerminalOutputSource source,
) {
  /// How far this segment has already been consumed or deliberately trimmed.
  int head = 0;

  int get remaining => text.length - head;

  String get remainingText => head == 0 ? text : text.substring(head);
}

/// Everything one terminal session needs to get PTY output onto the screen:
/// the backlog waiting to be written and the cadence at which it is flushed.
///
/// Kept apart from the session handle because it is a self-contained piece of
/// state with its own invariants, and the handle is already large enough that
/// adding to it obscures both.
class _TerminalOutputPipeline {
  /// Pending output held as whole chunks rather than one growing buffer: a
  /// single buffer forced a full copy plus two substrings on every drain, so
  /// draining a full backlog was quadratic in its size. Each segment owns its
  /// consumed head so live output behind a restore can be trimmed without
  /// copying or discarding the protected prefix.
  final Queue<_TerminalOutputSegment> pending = Queue<_TerminalOutputSegment>();

  /// Chars still to write across every source.
  int length = 0;

  /// Live chars subject to the runaway-output backlog cap.
  int liveLength = 0;

  /// Snapshot chars that still have to reach the emulator.
  int restoreLength = 0;

  /// A flush is pending, either as a frame callback or as a deferred timer.
  bool flushScheduled = false;

  /// Set while a flush is waiting out the cadence floor rather than the next
  /// frame. See `_terminalOutputMinFlushInterval`.
  Timer? flushTimer;

  /// Time since the last flush was *requested*. Not started until the first
  /// one, so the first chunk after an idle terminal is never delayed.
  final Stopwatch sinceFlushRequest = Stopwatch();

  /// Flushes performed, so a benchmark can read back the cadence the terminal
  /// actually drove rather than infer it from frame counts a test binding
  /// produces on its own.
  int flushCount = 0;

  void add(_TerminalOutputSegment segment) {
    pending.add(segment);
    length += segment.remaining;
    switch (segment.source) {
      case _TerminalOutputSource.restore:
        restoreLength += segment.remaining;
        break;
      case _TerminalOutputSource.control:
        break;
      case _TerminalOutputSource.live:
        liveLength += segment.remaining;
        break;
    }
  }

  void consume(_TerminalOutputSegment segment, int chars) {
    assert(chars >= 0 && chars <= segment.remaining);
    if (chars <= 0) {
      return;
    }
    segment.head += chars;
    length -= chars;
    switch (segment.source) {
      case _TerminalOutputSource.restore:
        restoreLength -= chars;
        break;
      case _TerminalOutputSource.control:
        break;
      case _TerminalOutputSource.live:
        liveLength -= chars;
        break;
    }
    if (segment.remaining > 0) {
      return;
    }
    if (pending.isNotEmpty && identical(pending.first, segment)) {
      pending.removeFirst();
    } else {
      pending.remove(segment);
    }
  }

  int offsetOf(_TerminalOutputSegment target) {
    var offset = 0;
    for (final segment in pending) {
      if (identical(segment, target)) {
        return offset;
      }
      offset += segment.remaining;
    }
    throw StateError('Terminal output segment is not pending.');
  }

  void restartFlushClock() => sinceFlushRequest
    ..reset()
    ..start();

  void cancelDeferredFlush() {
    final timer = flushTimer;
    timer?.cancel();
    flushTimer = null;
    // A queued frame has no timer and must keep owning the scheduled flush.
    // Cancelling a timer, however, releases that ownership so replacement
    // output can schedule itself.
    if (timer != null) {
      flushScheduled = false;
    }
  }

  void clear() {
    pending.clear();
    length = 0;
    liveLength = 0;
    restoreLength = 0;
  }
}

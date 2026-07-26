part of 'terminal_runtime.dart';

/// Everything one terminal session needs to get PTY output onto the screen:
/// the backlog waiting to be written and the cadence at which it is flushed.
///
/// Kept apart from the session handle because it is a self-contained piece of
/// state with its own invariants, and the handle is already large enough that
/// adding to it obscures both.
class _TerminalOutputPipeline {
  /// Pending output held as whole chunks rather than one growing buffer: a
  /// single buffer forced a full copy plus two substrings on every drain, so
  /// draining a full backlog was quadratic in its size. The head chunk is
  /// consumed in place through [head] for the same reason; a restored snapshot
  /// arrives as one multi-megabyte chunk.
  final Queue<String> pending = Queue<String>();

  /// How far the head chunk has already been consumed.
  int head = 0;

  /// Chars still to write, already net of [head].
  int length = 0;

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

  /// Chars left in the head chunk.
  int get headRemaining => pending.first.length - head;

  void restartFlushClock() => sinceFlushRequest
    ..reset()
    ..start();

  void cancelDeferredFlush() {
    flushTimer?.cancel();
    flushTimer = null;
  }

  void clear() {
    pending.clear();
    head = 0;
    length = 0;
  }
}

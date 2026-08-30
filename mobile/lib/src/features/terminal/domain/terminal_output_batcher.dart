import 'dart:async';
import 'dart:collection';

import 'package:alera_mobile/src/features/terminal/domain/terminal_restore_progress.dart';
import 'package:flutter/scheduler.dart';

/// Coalesces terminal output into one write per frame.
///
/// Without this every PTY chunk hits the emulator immediately, so a noisy
/// build parses and repaints many times inside a single frame. That is the
/// cost the desktop app removed; on a phone there is even less headroom.
///
/// Chunks are kept whole in a queue rather than concatenated into one growing
/// buffer: a single buffer forces a full copy plus a substring on every drain,
/// which makes draining a backlog quadratic in its size.
class TerminalOutputBatcher({
  required final void Function(String text) write,
  this.onRestoreProgress,
  final int maxCharsPerFrame = _defaultMaxCharsPerFrame,
  final int maxPendingChars = _defaultMaxPendingChars,
  final Duration minFlushInterval = _defaultMinFlushInterval,
  this.scheduleFrame,
}) {
  static const int _defaultMaxCharsPerFrame = 64 * 1024;
  static const int _defaultMaxPendingChars = 512 * 1024;
  static const Duration _defaultMinFlushInterval = Duration(milliseconds: 33);

  /// Reports how far a restored snapshot has been written, and null once it is
  /// fully in. The surface covers the emulator until then, because a restore
  /// spans many frames and watching history scroll past reads as a bug.
  final void Function(TerminalRestoreProgress? progress)? onRestoreProgress;

  /// Injected only by tests, which capture and drive frame requests by hand.
  final void Function(void Function() callback)? scheduleFrame;

  final Queue<_PendingOutputChunk> _pending = Queue<_PendingOutputChunk>();
  final Stopwatch _sinceFlushRequest = Stopwatch();
  int _pendingChars = 0;
  int _pendingLiveChars = 0;
  int _restoreTotalChars = 0;
  int _restoreWrittenChars = 0;
  bool _flushScheduled = false;
  bool _disposed = false;
  Timer? _flushTimer;

  int get pendingChars => _pendingChars;

  bool get debugRestoring => _restoreTotalChars > 0;

  /// Test-only evidence that a partial drain advances inside the original
  /// string instead of allocating a fresh tail after every frame.
  Object? get debugPendingHeadStorage =>
      _pending.isEmpty ? null : _pending.first.text;

  int get debugPendingHeadOffset => _pending.isEmpty ? 0 : _pending.first.head;

  bool get debugFlushDeferred => _flushTimer != null;

  /// Queues live output. Oldest output is dropped past the backlog cap, since
  /// a runaway process must not grow memory without bound and what the user is
  /// looking at is the newest output.
  void add(String text) => _enqueue(text, source: .live);

  /// Queues a restored snapshot, which is a bounded one-shot payload and so is
  /// exempt from the cap that exists to contain a live process.
  void addSnapshot(String text) {
    if (_disposed || text.isEmpty) {
      return;
    }
    _restoreTotalChars += text.length;
    _publishRestoreProgress();
    _enqueue(text, source: .restore);
  }

  void _enqueue(String text, {required _OutputSource source}) {
    if (_disposed || text.isEmpty) {
      return;
    }
    _pending.add(_PendingOutputChunk(text, source));
    _pendingChars += text.length;
    if (source == _OutputSource.live) {
      _pendingLiveChars += text.length;
      _trimLiveBacklog();
    }
    _schedule();
  }

  void _trimLiveBacklog() {
    while (_pendingLiveChars > maxPendingChars) {
      final chunk = _pending.firstWhere(
        (candidate) => candidate.source == _OutputSource.live,
      );
      final excess = _pendingLiveChars - maxPendingChars;
      final trim = excess < chunk.remaining ? excess : chunk.remaining;
      final target = _headTrimStart(chunk.text, chunk.head + trim);
      final dropped = target - chunk.head;
      if (dropped == chunk.remaining) {
        _consume(chunk, dropped);
        continue;
      }
      _pendingChars -= dropped;
      _pendingLiveChars -= dropped;
      // This copy is intentional and happens only when output is discarded:
      // retaining a single oversized source string would defeat the RAM cap.
      chunk
        ..text = chunk.text.substring(target)
        ..head = 0;
    }
  }

  void _schedule() {
    if (_flushScheduled || _disposed) {
      return;
    }
    final sinceLastRequest = _sinceFlushRequest.isRunning
        ? _sinceFlushRequest.elapsed
        : minFlushInterval;
    if (sinceLastRequest >= minFlushInterval) {
      _requestFrame();
      return;
    }
    _flushScheduled = true;
    _flushTimer = Timer(minFlushInterval - sinceLastRequest, () {
      _flushTimer = null;
      _flushScheduled = false;
      if (!_disposed) {
        _requestFrame();
      }
    });
  }

  void _requestFrame() {
    _flushScheduled = true;
    _sinceFlushRequest
      ..reset()
      ..start();
    final testScheduler = scheduleFrame;
    if (testScheduler != null) {
      testScheduler(flushFrame);
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback((_) => flushFrame());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Writes at most one frame's worth, splitting only the chunk that straddles
  /// the budget so the rest stays untouched.
  void flushFrame() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushScheduled = false;
    if (_disposed || _pending.isEmpty) {
      return;
    }
    final frame = StringBuffer();
    var written = 0;
    var restoreWritten = 0;
    while (_pending.isNotEmpty && written < maxCharsPerFrame) {
      final chunk = _pending.first;
      final remaining = maxCharsPerFrame - written;
      if (chunk.remaining <= remaining) {
        final available = chunk.remaining;
        frame.write(chunk.remainingText);
        final restore = chunk.source == _OutputSource.restore;
        _consume(chunk, available);
        written += available;
        if (restore) {
          restoreWritten += available;
        }
        continue;
      }
      final cutoff = _chunkCutoff(chunk.text, chunk.head + remaining);
      if (cutoff <= chunk.head) {
        break;
      }
      final consumed = cutoff - chunk.head;
      frame.write(chunk.text.substring(chunk.head, cutoff));
      final restore = chunk.source == _OutputSource.restore;
      _consume(chunk, consumed);
      written += consumed;
      if (restore) {
        restoreWritten += consumed;
      }
    }
    if (written > 0) {
      write(frame.toString());
    }
    _advanceRestore(restoreWritten);
    if (_pending.isNotEmpty) {
      _schedule();
    }
  }

  void _advanceRestore(int chars) {
    if (_restoreTotalChars <= 0) {
      return;
    }
    _restoreWrittenChars += chars;
    // Anything still queued behind the restore is live output that arrived
    // while it drained, so the cover comes down as soon as the history is in.
    if (_restoreWrittenChars >= _restoreTotalChars) {
      _restoreTotalChars = 0;
      _restoreWrittenChars = 0;
      onRestoreProgress?.call(null);
      return;
    }
    _publishRestoreProgress();
  }

  void _publishRestoreProgress() {
    onRestoreProgress?.call(
      TerminalRestoreProgress(
        writtenChars: _restoreWrittenChars,
        totalChars: _restoreTotalChars,
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    _sinceFlushRequest.stop();
    _pending.clear();
    _pendingChars = 0;
    _pendingLiveChars = 0;
    // A batcher discarded mid-restore has to take its own cover down: nothing
    // else clears it, and the emulator it belonged to is already gone.
    final restoring = _restoreTotalChars > 0;
    _restoreTotalChars = 0;
    _restoreWrittenChars = 0;
    if (restoring) {
      onRestoreProgress?.call(null);
    }
  }

  void _consume(_PendingOutputChunk chunk, int count) {
    chunk.head += count;
    _pendingChars -= count;
    if (chunk.source == _OutputSource.live) {
      _pendingLiveChars -= count;
    }
    if (chunk.remaining == 0) {
      _pending.remove(chunk);
    }
  }
}

enum _OutputSource { live, restore }

class _PendingOutputChunk(var String text, final _OutputSource source) {
  int head = 0;

  int get remaining => text.length - head;
  String get remainingText => head == 0 ? text : text.substring(head);
}

/// Never cuts between a surrogate pair, which would corrupt the code point.
int _chunkCutoff(String value, int limit) {
  if (value.length <= limit) {
    return value.length;
  }
  final codeUnit = value.codeUnitAt(limit);
  if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
    return limit - 1;
  }
  return limit;
}

int _headTrimStart(String value, int start) {
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

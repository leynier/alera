import 'dart:collection';

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
class TerminalOutputBatcher {
  TerminalOutputBatcher({
    required this.write,
    this.maxCharsPerFrame = _defaultMaxCharsPerFrame,
    this.maxPendingChars = _defaultMaxPendingChars,
    this.scheduler,
  });

  static const int _defaultMaxCharsPerFrame = 64 * 1024;
  static const int _defaultMaxPendingChars = 512 * 1024;

  final void Function(String text) write;
  final int maxCharsPerFrame;
  final int maxPendingChars;

  /// Injected only by tests, which drive frames by hand.
  final SchedulerBinding? scheduler;

  final Queue<String> _pending = Queue<String>();
  int _pendingChars = 0;
  bool _flushScheduled = false;
  bool _disposed = false;

  int get pendingChars => _pendingChars;

  /// Queues live output. Oldest output is dropped past the backlog cap, since
  /// a runaway process must not grow memory without bound and what the user is
  /// looking at is the newest output.
  void add(String text) => _enqueue(text, bounded: true);

  /// Queues a restored snapshot, which is a bounded one-shot payload and so is
  /// exempt from the cap that exists to contain a live process.
  void addSnapshot(String text) => _enqueue(text, bounded: false);

  void _enqueue(String text, {required bool bounded}) {
    if (_disposed || text.isEmpty) {
      return;
    }
    _pending.add(text);
    _pendingChars += text.length;
    if (bounded) {
      while (_pendingChars > maxPendingChars && _pending.length > 1) {
        _pendingChars -= _pending.removeFirst().length;
      }
      if (_pendingChars > maxPendingChars) {
        final chunk = _pending.removeFirst();
        final start = _headTrimStart(chunk, chunk.length - maxPendingChars);
        _pending.addFirst(chunk.substring(start));
        _pendingChars = chunk.length - start;
      }
    }
    _schedule();
  }

  void _schedule() {
    if (_flushScheduled || _disposed) {
      return;
    }
    _flushScheduled = true;
    final binding = scheduler ?? SchedulerBinding.instance;
    binding.scheduleFrameCallback((_) => flushFrame());
    binding.ensureVisualUpdate();
  }

  /// Writes at most one frame's worth, splitting only the chunk that straddles
  /// the budget so the rest stays untouched.
  void flushFrame() {
    _flushScheduled = false;
    if (_disposed || _pending.isEmpty) {
      return;
    }
    final frame = StringBuffer();
    var written = 0;
    while (_pending.isNotEmpty && written < maxCharsPerFrame) {
      final chunk = _pending.first;
      final remaining = maxCharsPerFrame - written;
      if (chunk.length <= remaining) {
        _pending.removeFirst();
        _pendingChars -= chunk.length;
        frame.write(chunk);
        written += chunk.length;
        continue;
      }
      final cutoff = _chunkCutoff(chunk, remaining);
      if (cutoff == 0) {
        break;
      }
      _pending.removeFirst();
      _pending.addFirst(chunk.substring(cutoff));
      _pendingChars -= cutoff;
      frame.write(chunk.substring(0, cutoff));
      written += cutoff;
    }
    if (written > 0) {
      write(frame.toString());
    }
    if (_pending.isNotEmpty) {
      _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _pendingChars = 0;
  }
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

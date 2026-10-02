import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Default ceiling per file, and how many files are kept.
///
/// Rotation is by size rather than by date so the disk cost stays predictable:
/// a quiet week and a crash loop both stay inside the same bound.
const int kDefaultLogMaxBytes = 5 * 1024 * 1024;
const int kDefaultLogMaxFiles = 5;

/// Limits the amount of log data waiting for the operating system.
///
/// Logging is best effort. A broken or slow filesystem must not let an error
/// storm retain every serialized record in memory until the disk catches up.
const int kDefaultLogMaxPendingBytes = 256 * 1024;

/// Flushes the underlying [IOSink] at bounded intervals so its internal buffer
/// cannot grow with a long-running burst of log records.
const int kDefaultLogFlushBytes = 64 * 1024;

class _PendingLogLine {
  _PendingLogLine({
    required this.line,
    required this.bytes,
    required this.completer,
  });

  final String line;
  final int bytes;
  final Completer<void> completer;
}

/// Appends lines to a size-bounded file with a fixed number of backups.
///
/// Writes are drained asynchronously rather than awaited by callers so
/// logging never blocks the frame pipeline. One drain serializes rotation
/// against in-flight writes, while a bounded pending queue caps memory use.
class RotatingLogSink {
  RotatingLogSink({
    required this.directory,
    required this.baseName,
    this.maxBytes = kDefaultLogMaxBytes,
    this.maxFiles = kDefaultLogMaxFiles,
    this.maxPendingBytes = kDefaultLogMaxPendingBytes,
    this.flushBytes = kDefaultLogFlushBytes,
  }) {
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
    }
    if (maxFiles <= 0) {
      throw ArgumentError.value(maxFiles, 'maxFiles', 'must be positive');
    }
    if (maxPendingBytes <= 0) {
      throw ArgumentError.value(
        maxPendingBytes,
        'maxPendingBytes',
        'must be positive',
      );
    }
    if (flushBytes <= 0) {
      throw ArgumentError.value(flushBytes, 'flushBytes', 'must be positive');
    }
  }

  IOSink? _sink;
  int _written = 0;
  int _bufferedBytes = 0;
  int _pendingBytes = 0;
  final Queue<_PendingLogLine> _pending = Queue<_PendingLogLine>();
  Future<void>? _drainFuture;
  bool _closed = false;
  bool _disabled = false;

  final Directory directory;
  final String baseName;
  final int maxBytes;
  final int maxFiles;
  final int maxPendingBytes;
  final int flushBytes;

  /// Path of the active file (index 0) or of one of its backups.
  File fileFor(int index) {
    final name = index == 0 ? '$baseName.log' : '$baseName.$index.log';
    return File(p.join(directory.path, name));
  }

  /// Queues [line] for writing. The returned future completes once this line
  /// has been handed to the file, but callers are free to ignore it. When a
  /// filesystem is slower than the producer, the oldest pending lines are
  /// discarded to keep logging memory bounded.
  Future<void> writeLine(String line) {
    if (_closed || _disabled) {
      return Future<void>.value();
    }

    final bytes = _utf8BytesWithinBudget(line, maxPendingBytes);
    final completer = Completer<void>();
    if (bytes == null) {
      // A single stack trace can be larger than the entire pending budget.
      // Count its UTF-8 representation incrementally so dropping it does not
      // allocate a second copy of a potentially unbounded stack trace.
      _complete(completer);
      return completer.future;
    }
    while (_pending.isNotEmpty && _pendingBytes + bytes > maxPendingBytes) {
      final dropped = _pending.removeFirst();
      _pendingBytes -= dropped.bytes;
      _complete(dropped.completer);
    }
    _pending.add(
      _PendingLogLine(line: line, bytes: bytes, completer: completer),
    );
    _pendingBytes += bytes;
    _startDrain();
    return completer.future;
  }

  void _startDrain() {
    if (_drainFuture != null) {
      return;
    }
    final drain = _drain();
    _drainFuture = drain;
    unawaited(
      drain.then<void>(
        (_) => _finishDrain(drain),
        onError: (Object _, StackTrace _) {
          // Keep even an unexpected queue failure out of the root zone. The
          // normal write path catches filesystem failures per record, but the
          // drain watcher is the final boundary for logging work.
          _disableSink();
          _finishDrain(drain);
        },
      ),
    );
  }

  void _finishDrain(Future<void> drain) {
    if (identical(_drainFuture, drain)) {
      _drainFuture = null;
      if (_pending.isNotEmpty && !_disabled) {
        _startDrain();
      }
    }
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final pending = _pending.removeFirst();
      _pendingBytes -= pending.bytes;
      try {
        await _writeLine(pending.line, pending.bytes);
      } on Object {
        // A logging failure must stay silent: reporting it through the logger
        // would recurse straight back into this sink.
        _disableSink();
        _dropPending();
      } finally {
        _complete(pending.completer);
      }
      if (_disabled) {
        return;
      }
    }
  }

  void _dropPending() {
    while (_pending.isNotEmpty) {
      final pending = _pending.removeFirst();
      _pendingBytes -= pending.bytes;
      _complete(pending.completer);
    }
    _pendingBytes = 0;
  }

  void _complete(Completer<void> completer) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _writeLine(String line, int bytes) async {
    await _ensureOpen();
    if (_disabled) {
      return;
    }
    // Rotating only when something is already written keeps a single record
    // larger than the cap from producing an endless run of empty files.
    if (_written > 0 && _written + bytes > maxBytes) {
      await _rotate();
    }
    if (_disabled) {
      return;
    }
    final sink = _sink;
    if (sink == null) {
      return;
    }
    sink.writeln(line);
    _written += bytes;
    _bufferedBytes += bytes;
    if (_bufferedBytes >= flushBytes) {
      await sink.flush();
      _bufferedBytes = 0;
    }
  }

  Future<void> _ensureOpen() async {
    if (_sink != null || _disabled) {
      return;
    }
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final active = fileFor(0);
    _written = active.existsSync() ? await active.length() : 0;
    final sink = active.openWrite(mode: .append);
    _sink = sink;
    // IOSink reports write failures through `done`, after `writeln` has
    // returned. Attach a listener at creation time so a bad descriptor cannot
    // become an uncaught async error in the application zone.
    unawaited(
      sink.done.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          _disableSink(sink);
        },
      ),
    );
  }

  Future<void> _rotate() async {
    // Close before renaming: Windows refuses to rename an open file.
    await _closeSink();
    if (_disabled) {
      return;
    }
    _written = 0;

    if (maxFiles <= 1) {
      final active = fileFor(0);
      if (active.existsSync()) {
        await active.delete();
      }
      await _ensureOpen();
      return;
    }

    final oldest = fileFor(maxFiles - 1);
    if (oldest.existsSync()) {
      await oldest.delete();
    }
    for (var index = maxFiles - 2; index >= 1; index--) {
      final from = fileFor(index);
      if (from.existsSync()) {
        await from.rename(fileFor(index + 1).path);
      }
    }
    final active = fileFor(0);
    if (active.existsSync()) {
      await active.rename(fileFor(1).path);
    }
    await _ensureOpen();
  }

  Future<void> _closeSink() async {
    final sink = _sink;
    _sink = null;
    _bufferedBytes = 0;
    if (sink == null) {
      return;
    }
    try {
      await sink.flush();
      await sink.close();
    } on Object {
      _disableSink();
    }
  }

  void _disableSink([IOSink? failedSink]) {
    if (failedSink != null && !identical(_sink, failedSink)) {
      return;
    }
    _sink = null;
    _bufferedBytes = 0;
    _disabled = true;
    _dropPending();
  }

  /// Waits for queued writes to reach the file.
  Future<void> flush() async {
    final drain = _drainFuture;
    if (drain != null) {
      await drain;
    }
    final sink = _sink;
    if (sink == null) {
      return;
    }
    try {
      await sink.flush();
      _bufferedBytes = 0;
    } on Object {
      _disableSink(sink);
    }
  }

  Future<void> close() async {
    _closed = true;
    final drain = _drainFuture;
    if (drain != null) {
      await drain;
    }
    _dropPending();
    await _closeSink();
  }

  /// Existing log files, newest first, for collection into a bundle.
  List<File> existingFiles() {
    return <File>[for (var index = 0; index < maxFiles; index++) fileFor(index)]
        .where((file) => file.existsSync())
        .toList();
  }
}

/// Returns the UTF-8 byte length including the line terminator, or `null` if
/// the representation exceeds [maxBytes]. This mirrors Dart's UTF-8 encoder:
/// malformed UTF-16 code units become the three-byte replacement character,
/// while valid surrogate pairs become one four-byte scalar. Counting before
/// encoding keeps an oversized log record from allocating a huge byte list on
/// the main isolate.
int? _utf8BytesWithinBudget(String line, int maxBytes) {
  var bytes = 1; // writeln appends one ASCII line-feed byte.
  for (var index = 0; index < line.length; index++) {
    final codeUnit = line.codeUnitAt(index);
    final additionalBytes = switch (codeUnit) {
      <= 0x7f => 1,
      <= 0x7ff => 2,
      >= 0xd800 && <= 0xdbff
          when index + 1 < line.length &&
              line.codeUnitAt(index + 1) >= 0xdc00 &&
              line.codeUnitAt(index + 1) <= 0xdfff =>
        4,
      >= 0xd800 && <= 0xdfff => 3,
      _ => 3,
    };
    bytes += additionalBytes;
    if (bytes > maxBytes) {
      return null;
    }
    if (additionalBytes == 4) {
      index++;
    }
  }
  return bytes;
}
